/** opa-dynamic
  * Monitor a directory conataining a project, recompiles it and relaunch it when needed
  */

import stdlib.io.file
import stdlib.core.concurrency
import stdlib.system

do Scheduler.sleep(1, -> main(CommandLine.filter(CommandLineConf)) ) // Workaround


@expand
debug = #<Ifstatic:DEBUG> s -> println("[DEBUG] {s}") #<Else> _ -> void #<End>

type config.notifier = {notify_send} / {terminal_notifier} / {none}

/** Configuration for one project directory */
type config = {
  command : list(string) // list of command , inferred if empty
  directory : string     // project directory
  avoid_dir : list(string)
  avoid_ext : list(string)
  avoid_prefix : list(string)
  launch : bool
  opa_opt : string
  notifier : config.notifier
}


// Add browser support, launch and reload
DConfig = {{
  /** Control grouping delay of sequential events */
  grouping_delay = Duration.ms(300)
  config = {
    command = [] // empty => inferred
    directory="."
    avoid_dir=[".git", "_build", "_tracks","node_modules"]
    avoid_ext=[".opx", "_depends"/*opa*/, ".log", ".bak", ".old", "~"/*emacs*/, ".exe"]
    avoid_prefix =[ ".#"/*emacs*/, "#" ]
    launch = true
    opa_opt = ""
    notifier = {notify_send}
  }
}}

CommandLineConf = {{
  title = "OpaDyn"
  init = DConfig.config
  anonymous = []
  parsers = [
    CommandLine.string(["--src-dir"],"Directory to auto-build","directory(={init.directory})"){
     s,c -> {c with directory = s}
    },
    CommandLine.string(["--avoid-dir"],"Directory to avoid","directory(={init.avoid_dir})"){
     s,c -> {c with avoid_dir=[s|c.avoid_dir]}
    },
    CommandLine.string(["--avoid-ext"],"Extension to avoid","extension(={init.avoid_ext})"){
     s,c -> {c with avoid_ext=[s|c.avoid_ext]}
    },
    CommandLine.string(["--command"],"Command to build","command(=inferred)"){
     s,c -> {c with command = [s|c.command]}
    },
    CommandLine.string(["--opa-opt"],"Option for opa command","opt"){
     s,c -> {c with opa_opt = "{c.opa_opt} {s}"}
    },
    CommandLine.switch(["--no-launch"],"Last command is not a launch command"){
     c -> {c with launch = false}
    },
    cases = [
      ("no", {none}),
      ("linux", {notify_send}),
      ("mac"  , {terminal_notifier}),
      ("windows", {none})
    ]
    CommandLine.case(["--notifier"],cases,
     "Force platform notifier", String.concat(" or ",List.map(_.f1, cases))
    ){
     n,c -> {c with notifier = n}
    },
  ]
}} : CommandLine.family(config)

avoid_file(config)(file) =
      List.mem(file,config.avoid_dir)
  ||  List.exists(String.has_suffix(_,file), config.avoid_ext)
  ||  List.exists(String.has_prefix(_,file), config.avoid_prefix)



type command_queue_state = MutexRef.t({
  need : bool
  in_progress : option(Date.date) // Some => in progress
})

type job = {
  name : string
  command : -> void
}

/** projecting a function to an exclusive access queue,
    only one function can be executed at the same time,
    new execution demand during a previous exectution will be merge into one exectution
    new execution demand that are very near in time are merged
*/
exclusive_queue(command: -> void) = (

  stateR = MutexRef.create({need=false progress=none})
  finished() = do debug("XQUEUE FINISHED") MutexRef.update(stateR){ state -> {state with progress=none} }
  start() = do debug("XQUEUE START") MutexRef.update(stateR){ state -> {state with progress=some(Date.now()) need=false} }
  consume_need()  = MutexRef.exclusive(stateR){ ->
    state = MutexRef.get(stateR)
    do debug("XQUEUE CONSUME NEED {state}")
    do MutexRef.set(stateR, {MutexRef.get(stateR) with need=false})
    state.need
  }
  rec proceed(id) =
    do debug("TRY PROCEED {id}")
    if MutexRef.get(stateR).progress!=none then debug("STILL IN PROGRESS") else
    do debug("PROCEED")
    do start()
    do command()
    do finished()
    if consume_need() then proceed(id)
    else debug("XQUEUE END LOOP, WAITING")

  -> MutexRef.update(stateR){ state ->
    // any transition to need=true without any in_progress work starts a new proceed_loop
    if state.need then do debug("STILL IN NEED") state else
    need = match state.progress
      {none} -> true
      {some=t} ->
        dt = Date.between(t,Date.now())
        do debug("DT = {Duration.in_milliseconds(dt)} ms")
        dt > DConfig.grouping_delay // if far enough after starting progress
      end
    do if need then Scheduler.push( -> proceed(Random.string(4)) )
    do debug("NEED = {need}")
    {state with ~need}
  }

)

/**
  * Listening a set of file, and triggering command on any change that is not about avoided files.
  */
job_on_files_changes(avoid_file,files,_name,command)=
  command=exclusive_queue(command)
  handler_map = MutexRef.create(StringMap.empty)
  _remove_file(file) = MutexRef.update(handler_map){
    map -> StringMap.remove(file, map)
  }
  command_if_not_avoid(file) = if not(avoid_file(file)) then command() else debug("AVOIDED {file}")
  add_file(file) =
    do debug("Listen {file} ")
    is_directory = File.is_directory(file)
    if not(is_directory) then void else
    handler = File.onchange(file,none){file1, event ->
      do  debug("EVENT[{file} {file1}] = {Debug.dump(event)}")
      match event
      {change=file2} ->
        do if is_directory then debug("file-change") else debug("mod-or-delete")
        command_if_not_avoid(file2)
      {rename=file2} ->
        do if is_directory then debug("new-or-delete") // TODO : HANDLE NEW FILE LISTENING HERE
                           else debug("delete")
        command_if_not_avoid(file2)
    }
    do MutexRef.update(handler_map){ map ->
      StringMap.add(file, handler, map)
    }
    debug("OK")

  do StringSet.iter(add_file,files)
  command()

only_directories = true

/** Collect recusively all path in a directory using an avoidance rule */
collect_files(avoid_file, rpath,dir) =
  path = List.rev([dir|rpath])
  pathstr = String.concat("/", path)
  v = File.readdir(pathstr):outcome(llarray(string), string)
  if avoid_file(dir) then []
  else match v
  {success=array} ->
    do debug("DIR={pathstr}")
    subs = LowLevelArray.mapi(array){ _i,v ->
      collect_files(avoid_file,[dir|rpath],v)
    } |> LowLevelArray.fold(List.cons,_,List.empty) |> List.flatten
    [path|subs]
  {failure=_} -> [path]


keep_n_first_lines(n,s) = String.explode("\n", s) |> List.take(n,_) |> String.concat("\n",_)
//keep_n_last_lines(n,s)  = String.explode("\n", s) |> List.rev |> List.take(n,_) |> List.rev |> String.concat("\n",_)

summary_error(s) =
  // TODO position could be simplified
  errors = String.explode("Error:", s)
  nb_errors = List.length(errors)
  if nb_errors > 0 then "Error:"^keep_n_first_lines(8, List.head(List.rev(errors))) else s

// 8 lines max
notify_send(title,mess,positive) =
  clear(s) = s |> String.replace("\"", " ", _) |> String.replace("\'", " ", _)
  icon = if positive then "-i dialog-ok-apply" else "-i dialog-warning"
  mess = summary_error(mess)
  do debug("NOTIFY {mess}")
  match System.shell_exec("notify-send {icon} -a Opa \"{clear(title)}\" \"{clear(mess)}\"","").result()
  {error={some=err} ...} -> debug("Notify failure : {err}")
  ~{stderr stdout ...} -> debug("Notify ok : <<{stdout}{stderr}>>")

notify =
| {notify_send} -> notify_send
| {terminal_notifier} | {none} -> (_,_,_ -> void)

simplified_dir(dir)= List.head(List.rev(String.explode("/",dir)))

Autocommand(config) = {{
  target= "dynamic.exe"
  kill_id = Random.string(16) // Workaround
  Conf = {{
    commands = ["opa {config.opa_opt} --opx-dir _build --conf *.conf --conf-opa-files -o {target}"] ++ if config.launch then ["cp ./{target} ./{kill_id}_{target} && ./{kill_id}_{target} -p 2001"] else []
  }}
  Opack = {{
    commands = ["opa {config.opa_opt} *.opack -o {target}"] ++ if config.launch then ["cp ./{target} ./{kill_id}_{target} && ./{kill_id}_{target} -p 2001"] else []
  }}
  Makefile = {{
    commands = ["make", ] ++ if config.launch then  ["make run"] else []
  }}
}}


main(config)=
  // Notifier
  notify_title = "{simplified_dir(config.directory)}"
  notify_title_error = "FAILURE : {notify_title}"
  notify_title_fine = "Launched : {notify_title}"
  notify = notify(config.notifier)
  // Avoidance rule
  avoid_file = avoid_file(config)
  Autocommand = Autocommand(config)
  // Remember last lauch to be able to kill it
  previous_last = MutexRef.create(none)
  may_kill_previous_last() = MutexRef.update(previous_last){ opt ->
    do debug("SHOULD KILL {opt}")
    do Option.iter(p -> do debug("TRY KILL {p.p.pid}") do p.p.kill() do Reference.set(p.killed, true) debug("KILLED {p.p.pid}"),opt)
      // An ugly work-around, need proper process group here
      do ignore(System.shell_exec("ps x -o pid,cmd | grep {Autocommand.kill_id} | cut -d ' ' -f 1 | xargs kill","").result())
      none
    }
  register_previous_last(p) = MutexRef.update(previous_last)(
    | {none} -> some(p)
    | {some=prev} -> do debug("{prev.p.pid} has not been killed") do prev.p.kill() some(p)
  )
  // do System.at_exit( -> do may_kill_previous_last(); /*do ignore(System.shell_exec("cd {config.directory} && rm {Autocommand.kill_id}_*","") );*/ void)
  set = Fold.list( collect_files(avoid_file,[],config.directory), StringSet.empty ){
		path, set -> StringSet.add(String.concat("/", path), set )
  }
  // Standard Opa project detection
  has_file(file) =  StringSet.mem(String.concat("/",[config.directory,file]), set)
  has_ext_file(ext) = StringSet.exists(String.has_suffix(ext,_),set)
  has_opack = has_ext_file(".opack")
  has_conf = has_ext_file(".conf")
  has_makefile = has_file("Makefile")
  commands() = (
     if config.command!=[] then config.command else
     if has_opack          then Autocommand.Opack.commands else
     if has_conf           then Autocommand.Conf.commands else
     if has_makefile       then Autocommand.Makefile.commands else []
  )
  do if commands()==[] then error("Don't know what to do please specify --command or create a .conf or .opack or Makefile file")
  command() =
    do print("Change detected: ")
    commands = commands()
    len = List.length(commands)
    is_last = (_ == len-1)
    fine = (List.foldi(_,commands,true)){ i, command, continue ->
    if not(continue) then false else
      command = "cd {config.directory} && {command}"
      do debug("COMMAND {command}")
      message = if config.command!=[] then "command {i}"
                else match i
                     0 -> "compilation"
                     1 -> "run"
                     _ -> "command {i}"
                     end
      do print(message)
      killed = Reference.create(false)
      process_outcome(o) = match o.error
        {none} -> do print(" OK, "); continue
        {some=_} -> if Reference.get(killed) then true else do println(" FAILURE <<\n{o.stderr}\n>>"); do notify(notify_title_error,o.stderr,false); false
        end
      async_launch_command = len>1 && is_last(i)
      do if async_launch_command then may_kill_previous_last()
      ~{p result} = System.shell_exec(command, "")
      do debug("LAUNCHED")
      do debug("LAUNCHED {p.pid}")
      if async_launch_command then
        do register_previous_last(~{p killed})
        do Scheduler.push{ ->
          do debug("WAIT {p.pid}")
          do ignore(process_outcome(result()))
          debug("ASYNC LAUNCH FINISHED {p.pid}")
        }
        true
      else
        do debug("WAIT {message}")
        r = process_outcome(result())
        do debug("DONE {message}")
        r
    }
    if fine then do println(" OK") notify(notify_title_fine,"",true) else debug("NOT FINE")
    job_on_files_changes(avoid_file,set,"_name", command)


