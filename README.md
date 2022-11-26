# awl - A command line tool for running larger scripts against a running AwesomeWM

If you use [Awesome](/awesomeWM/awesome), `awesome-client` can be a handy way to run snippets of Lua code against a running instance for debugging and one-off modifications.  But for longer scripts, while you _can_ just `cat` a Lua file into `awesome-client`, this approach has some drawbacks:

  * Getting output from such a script can be a little annoying - you can use `print()`, which will end up in Awesome's standard output, or you could use `naughty.notify`, which disappears after some time and isn't usable in a shell pipeline.
  * Loading modules via `require()` are loaded relative to your Awesome config directory, and due to Lua's module loader, are only loaded the first time they're used.

So this tool I wrote - `awl` - compensates for those shortcomings:

  * `print()` output goes to awl's standard output, so you can use it in a shell pipeline for analysis.
  * `require()` loads modules relative to the script you're running, and the "only load once" behavior is per-invocation of `awl`.

I wrote this to explore some memory-related issues I was having with Awesome, so there are a number of memory-related modules and scripts that are included in this repo.
