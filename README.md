![Angelspie logo](https://github.com/arnoo/angelspie/blob/master/logo/readme_header.png?raw=true)

Angelspie is a tool to apply rules to application windows on Linux: set their placement, workspace, decorations… based on window name, class, role…

Angelspie is designed for easy migration from Devilspie, which is unmaintained.

Compared to Devilspie, Angelspie has some added functionality for tiling and multi-monitor setups. It also repositions windows when display configuration changes (monitor added or removed for instance).

## Configuration

Angelspie reads any `.as` file in `~/.config/angelspie` and runs it in the context of each new window (and once for each window on startup or when display configuration changes).

Here's an example `.as` script that shows a few possibilities:

```hy
(when (= (window-class) "Calendar")
  (set-workspace 3)
  (undecorate)
  (tile-at "center-right"))

(when (= (window-class) "Pidgin")
  (spawn_async "xseticon" "-id" (window-xid) "/usr/share/icons/hicolor/48x48/apps/pidgin.png")
  (if (= (window-name) "Buddy List")
    (geometry "403x675+47+78")
    (geometry "1008x675+496+78")))

(when (in (window_class)
          ["Gitlab-board" "JIRA-board"])
  (when (monitor-connected "DP1")
    (set-monitor "DP1")
    (pin)
    (return))
  (set-workspace 5)
  (unpin)
  (tile-at "full"))
```

Angelspie is written in [Hy](http://hylang.org/) and so are its configuration files. Any Hy function or macro can be used in the configuration scripts. This means that you can do anything you can do with Python and more.

## Running

Standalone releases are not yet ready (help is more than welcome on the packaging front). You'll need to run the dev version for now:

- clone the git repository
- `cd` into it
- install the dependencies with `pipenv install`
- run using `pipenv run hy angelspie.hy`

Once you have your configuration files figured out, you might want to run angelspie on startup.

## Command line use

You can specify `.as` scripts or even code for Angelspie to evaluate.

Code passed to `--eval` is evaluated in the context of the active window.

For example, I have this bound to Super+Right in my desktop environment:
`angelspie --load=${HOME}/.config/angelspie/00-screen-conf.as --eval='(tile-at "right")'`
which will tile the active window right.

`00-screen-conf.as` contains:

```hy
(setting tile-margin-top    (if (> (monitor-width) 1800)
                                "6%"
                                (if (monitor-is-primary) 34 0)))
(setting tile-margin-bottom (if (> (monitor-width) 1800) "4%" 0))
(setting tile-margin-left   (if (> (monitor-width) 1800) "2%" 0))
(setting tile-margin-right  (if (> (monitor-width) 1800) "2%" 0))
(setting tile-col-gap       (if (> (monitor-width) 1800) "2%" 0))
(setting tile-row-gap       (if (> (monitor-width) 1800) "3%" 0))
```

It is loaded both in my keyboard shortcuts and as part of my global Angelspie configuration. This makes tiling adapt to the screen size and work exactly the same at the keyboard and in my Angelspie rules.

You can also run angelspie for a given window by passing the window id as hex or decimal:
`angelspie --wid 0x123AB23 --eval '(focus)'`

## APP specific tricks

### Emacs

Add this at the very beginning of your ~/.emacs/init.el to prevent Emacs from resizing the window after Angelspie does:

`(setq frame-inhibit-implied-resize t) ;; prevent resize window on startup`

### XFCE


This forces the XFCE workspace switcher to re-adjust to the new display geometry when unplugging a monitor.

```hy
(on-monitors-change
  (spawn-async "xfconf-query -c xfce4-panel -p /plugins/plugin-2/miniature-view -s false;
                xfconf-query -c xfce4-panel -p /plugins/plugin-2/miniature-view -s true"))
```

## Devilspie compatibility

If you start Angelspie and no configuration files exist, configuration files will be built based on your Devilspie config if you have one. 

In `.as` files, there are a few changes from Devilspie syntax made to avoid ugly redefinitions of Hy reserved words:
- `if` has been renamed `dsif` (for Devilspie `if`). The difference with Hy's builtin `if` is that the else clause is optional in `dsif`
- `is` is removed in favor of Hy's built-in `=`
- `print` has been renamed `dsprint`
- `str` has been renamed `str+`

By contrast with Devilspie, `geometry` considers coordinates relative to the window's current monitor (i.e. the one with most of the current window on it) unless you set `(setting ref-frame RefFrame.SCREEN)`.

The following Devilspie functions are as of yet unimplemented:
- `opacity`
- `set_viewport`
- `stick`
- `unstick`
- `wintype`
- `window_role`

You'll get a warning when your configuration script calls an undefined function. I welcome pull requests in the hope of making this at some point a complete drop-in replacement for Devilspie.

`skip_pager` and `skip_tasklist` can be called with a boolean to toggle skipping of pager/tasklist.

In Hy variable/function names `_` and `-` are the same, so `skip_pager` for instance can be called `skip-pager`, which is more lispy.

## Roadmap
- proper packaging and binary releases
- implement missing Devilspie functions
- CI and a solid non regression suite (maybe based on docker + virtual Xorg displays ?)
- make `browser-url` work properly on Chrome/Chromium
- provide better tools to work with browsers and make webapp management more acceptable

Contributions are welcome.

## API documentation
### DEVILSPIE FUNCTIONS/MACROS
#### `(application_name)`
Return the application name (as determined by libwnck) of the current window (String).

#### `(above)`
Set the current window to be above all normal windows, returns True.

#### `(begin #* forms)`
