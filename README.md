This is a tool to apply rules to windows on Linux: placement, workspace, tiling, decorations… based on window name, class, role…

This is intended as a drop-in replacement for devilspie which is unmaintained and now segfaults way too often.

Compared to devilspie, Angelspie has some added functionality for tiling. It also repositions windows when display configuration changes (screen added or removed for instance).

If you start angelspie and no configuration files exist, it will build configuration files based on your devilspie config if you have one. 

## Configuration

Angelspie reads any `.as` file in `~/.config/angelspie` and runs it in the context of each new window (and once for each window on startup or when display configuration changes).

Here's an example `.as` script that shows a few possibilities:

```
(when (= (window_class) "Calendar")
  (set_workspace 3)
  (undecorate)
  (tile "center-right"))

(when (= (window_class) "Pidgin")
  (spawn_async "xseticon" "-id" (window_xid) "/usr/share/icons/hicolor/48x48/apps/pidgin.png")
  (if (= (window_name) "Buddy List")
    (geometry "403x675+47+78")
    (geometry "1008x675+496+78")))

(when (or (= (window_class) "Gitlab-board")
          (= (window_class) "JIRA-board"))
  (tile "full"))
```

Angelspie is written in [hy](http://hylang.org/). Any hy function or macro can be used in the configuration scripts.

## Devilspie compatibility

The devilspie functions I was not using are not implemented but should not be too hard to hack based on the others. You'll get a warning when yoir configuration script calls an undefined function. I welcome pull requests in the hope of making this at some point a complete drop-in replacement for devilspie.

In `.as` files, there are a few changes from devilspie syntax made to avoid ugly redefinitions of hy/python reserved words:
- if has been renamed dsif (devilspie if). The difference with hy's builtin if is that the else clause is optional in dsif
- str has been renamed str+
- is has been renamed =

## Running

To run, use `pipenv run hy angelspie.hy` in the source directory.


## Command line use

I have this bound to Super+Left in my desktop environment:
`pipenv run hy angelspie.hy --load=${HOME}/.config/angelspie/00-screen-conf.as --eval='(my-tile "right")'`
which will tile the active window right

`00-screen-conf.as` contains:

```
(setv +large-screen+ (> (screen_width) 1000))

(defn my-tile [direction]
  (global +large-screen+)
  (if +large-screen+
    (tile direction 
          :screen-margin-top "6%"
          :screen-margin-bottom "4%"
          :screen-margin-left "2%"
          :screen-margin-right "2%"
          :window-margin-horizontal "2%"
          :window-margin-vertical "3%")
    (tile direction 
          :screen-margin-top 0
          :screen-margin-bottom 0
          :screen-margin-left 0
          :screen-margin-right 0
          :window-margin-horizontal 0
          :window-margin-vertical 0)))
```

This makes tiling adapt to the screen size and work exactly the same at the keyboard and in my Angelspie rules that also call my-tile to tile windows.
