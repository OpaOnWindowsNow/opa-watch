opa-dynamic
===========

## What is *opa-dynamic* ?
*opa-dynamic* provides a project-based 'verify & launch loop' for Opa. 
This makes developpement with Opa even more fun and more productive.

Each time you do a modification on your project, your project isautomatically verified by the *Opa* compiler (syntax, semantics, client/server distribution ...) and launched.
*opa-dynamic* is editor-independant so it will work in any environment.


## Is my project supported ?
It should work off-the-shelf with any project created by opa-create or containing an `opa.conf` or a `Makefile` files.
It can be easily customized to work with most projects.


## How to use it ?
Assuming your project is compatible with *opa-dynamic*, in a terminal, start *opa-dynamic*:

`opa-dynamic --src-dir path/opa_project`
Or just without argument when launched in the current directory.

You will be notifed of compilation error if any.
On the terminal you should have a message:

>Change detected: compilation OK, run OK

And you should have in your notification area the following message:

>Launched : opa_project


Edit any opa file inside, like the code for your project home page.
The previous two message appears again, indicating that the modification has been processed.
You can see the result immediatly using your browser. (`firefox localhost:2001`)

Edit again, when the message Launched appears, you can reload the home page and see the results of your modifications.

If your edit breaks the compilation or the launch, we will be notified.
For instance, if you introduce a type error, we will have the following notification:


>FAILURE : opa_project

>Error: File "src/view/page.opa", line 1, characters 3-7, (1:3-1:7 | 3-7)

>Type Conflict

>  (1:3-1:3)           int

>  (1:5-1:7)           float

>

>  The types of the first argument and the second argument

>    of function + of stdlib.core should be the same

You can correct the error and continue to work on your project, at any time the project is correct again, the last version will be launched and testable in your browser.


## Is my Makefile supported ?
If `make` build your project and `make run` launch or relaunch your project, then yes it is supported.


## My Makefile is not supported, what should I do ?
Assuming `make target1` is compiling your project, generating `target1.exe`.
You can do:
`opa-dynamic --src-dir path/opa_project --command "make target1.exe" --command "killall target1 && target1.exe"`
See "How to use with project with custom build rules?" for explanations.


## How to use with project with custom build rules ?

You can give the list of command to build and launch your project.
Be sure that relaunching is supported by terminating a previously launched version.
The last command is assumed to be the launch command and its termination is not waited for. (if not use `--no-launch`)
For instance:
`opa-dynamic --src-dir path/opa_project --command "build_command" --command "killall launch.exe" --comand "launch.exe"`

## How to use specific opa options without specifying `--command` ?
You can use `--opa-opt`.
For instance if your project is in classic syntax:
`opa-dynamic --src-dir path/opa_project --opa-opt "--parser classic"`

## How to avoid the `--src-dir` option ?
The current directory will be use if `--src-dir` is omitted.

## Are Mac and Windows supported ?
*opa-dynamic* should work but the notification feature is not working yet. 

## Can notification appeared in my favorite text editor ?
We plan to support notification in emacs and Sublime Text, and to provide a simple way to have it on other editor.

## Can I make opa-dynamic better ?
Yes you are welcomed for any contributions, bug fixes, doc fixes and new features.

## What is the license?
*opa-dynamic* is released under the MIT license.