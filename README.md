Angelspie is a tool to apply rules to windows on Linux: placement, workspace, tiling, decorations… based on window name, class, role…

Angelspie is intended as a drop-in replacement for Devilspie which is unmaintained and now segfaults way too often.

Compared to Devilspie, Angelspie has some added functionality for tiling. It also repositions windows when display configuration changes (screen added or removed for instance).

If you start Angelspie and no configuration files exist, it will build configuration files based on your Devilspie config if you have one. 

## Configuration

Angelspie reads any `.as` file in `~/.config/angelspie` and runs it in the context of each new window (and once for each window on startup or when display configuration changes).

Here's an example `.as` script that shows a few possibilities:

```
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
  (tile-at "full")
  (when (monitor-connected "DP1")
    (set-monitor "DP1")
    (pin)))
```

Angelspie is written in [Hy](http://hylang.org/) and so are its configuration files. Any Hy function or macro can be used in the configuration scripts. This means that you can do anything you can do with Python and more.

## Devilspie compatibility

In `.as` files, there are a few changes from Devilspie syntax made to avoid ugly redefinitions of Hy reserved words:
- `geometry` considers coordinates relative to the window's current monitor (i.e. the one with most of the current window on it) unless you set `(settings ref-frame RefFrame.SCREEN)`
- `if` has been renamed `dsif` (for Devilspie `if`). The difference with Hy's builtin `if` is that the else clause is optional in `dsif`
- `is` is removed in favor of Hy's built-in `=`
- `print` has been renamed `dsprint`
- `str` has been renamed `str+`

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


## Running

To run, use `pipenv run hy angelspie.hy` in the source directory.

## Command line use

You can specify `.as` scripts or even code for Angelspie to evaluate.

Code passed to `--eval` is evaluated in the context of the active window.

For example, I have this bound to Super+Right in my desktop environment:
`pipenv run hy angelspie.hy --load=${HOME}/.config/angelspie/00-screen-conf.as --eval='(tile-at "right")'`
which will tile the active window right.

`00-screen-conf.as` contains:

```
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

## APP specific tricks

### Emacs

Add this at the very beginning of your ~/.emacs/init.el to prevent Emacs from resizing the window after Angelspie does:

`(setq frame-inhibit-implied-resize t) ;; prevent resize window on startup`


### Firefox

Angelspie combined with "I Hate Tabs - SDI extension" gives you Firefox with tiling windows instead of tabs.


## API documentation

### DEVILSPIE FUNCTIONS/MACROS
#### `(application_name )`
Return the application name (as determined by libwnck) of the current window (String).

#### `(above )`
Set the current window to be above all normal windows, returns True.

#### `(begin #*forms)`
The devilspie equivalent of Hy's `do` : evaluates all the function calls within, returns the result of the last evaluation.

#### `(below )`
Set the current window to be below all normal windows, returns True.

#### `(center )`
Center position of current window, returns boolean.

#### `(close )`
Close the current window, returns True.

#### `(contains string substring)`
True if string contains substring.

#### `(debug )`
Debugging function, outputs the current window's title, name, role and geometry (Returns TRUE).

#### `(decorate )`
Add the window manager decorations to the current window, returns boolean.

#### `(dsif cond-clause then-clause [else-clause None])`
Equivalent to Devilspie's if. Like Hy's builtin if, but the else clause is optional.
   Evaluates then-clause if cond-clause is True, else-clause otherwise if provided.

#### `(dsprint #*args)`
Equivalent to Devilspie's print.
   Print args without trailing newline, returns boolean.

#### `(focus )`
Focus the current window, returns True.

#### `(fullscreen )`
Make the current window fullscreen, returns True.

#### `(geometry geom-str)`
Set position + size (as string) of current window, returns boolean.
   geom-str should be in X-GeometryString format:
    [=][<width>{xX}<height>][{+-}<xoffset>{+-}<yoffset>]
   as an extension to the X-GeometryString format, all values
   can be specified as percentages of screen/monitor size. For
   percentages of screen size, set setting "ref-frame" to RefFrame.SCREEN
   Examples:
       (geometry "400×300+0-22")
       (geometry "640×480")
       (geometry "100%×50%+0+0")
       (geometry "+10%+10%")

#### `(matches string pattern)`
True if the regexp pattern matches str

#### `(opacity level)`
Change the opacity level (as integer in 0..100) of the current window, returns boolean.

#### `(maximize )`
Maximise the current window, returns True.

#### `(maximize_vertically )`
Maximise vertically the current window, returns True.

#### `(maximize_horizontally )`
Maximise horizontally the current window, returns True.

#### `(minimize )`
Minimise the current window, returns True.

#### `(pin )`
Pin the current window to all workspaces, returns True.

#### `(println #*args)`
Print args with trailing newline, returns True.

#### `(set_viewport viewport-nb)`
Move the window to a specific viewport number, counting from 1, returns boolean.

#### `(set_workspace workspace-nb)`
Move the window to a specific workspace number, counting from 1, returns boolean.

#### `(shade )`
Shade ('roll up') the current window, returns True.

#### `(skip_pager [active True])`
Remove the current window from the window list, returns True.
   If passed active=False, puts the window back in the window list.

#### `(skip_tasklist [active True])`
Remove the current window from the pager, returns True.
   If passed active=False, puts the window back in the pager.

#### `(spawn_async #*cmd)`
Execute a command in the background, returns boolean. Command is given as a single string, or as a series of strings (similar to execl).

#### `(spawn_sync #*cmd)`
Execute  a  command in the foreground (returns command output as string, or FALSE on error). Command is given as a single string, or as a series of strings (similar to execl).

#### `(stick )`
Make the current window stick to all viewports, returns True.

#### `(str+ #*args)`
Transform parameters into strings and concat them with spaces in between.

#### `(undecorate )`
Remove the window manager decorations from the current window, returns boolean.

#### `(unmaximize )`
Un-maximise the current window, returns True.

#### `(unminimize )`
Un-minimise the current window, returns True.

#### `(unpin )`
Unpin the current window from all workspaces, returns True.

#### `(unshade )`
Un-shade ('roll down') the current window, returns True.

#### `(unstick )`
Unstick the window from viewports, returns True.

#### `(wintype type)`
Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop.

#### `(window_class )`
Return the class of the current window (String).

#### `(window_name )`
Return the title of the current window (String).

#### `(window_property prop-name)`
Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String).

#### `(window_role )`
Return the role (as determined by the WM_WINDOW_ROLE hint) of the current window (String).

#### `(window_workspace )`
Returns the workspace the current window is on (Integer).

#### `(window_xid )`
Return the X11 window id of the current window (Integer).

### ADDITIONS TO DEVILSPIE
#### `(setting varname value)`
Set Angelspie setting <varname> to the result of evaluating val-form
   in each window/monitor/etc. context where the setting is needed.

#### `(monitor )`
Returns the connector name of the current window's monitor (i.e. the one that has most of the window in it).

#### `(monitor-connected connector-name)`
Returns True if monitor with connector connector-name is connected, false otherwise

#### `(monitor-height )`
Returns the height in pixels of the current window's monitor (i.e. the one that has most of the window in it).

#### `(monitor-is-primary )`
Returns True if the current window's monitor (i.e. the one that has most of the window in it) is primary, False otherwise.

#### `(monitor-width )`
Returns the width in pixels of the current window's monitor (i.e. the one that has most of the window in it).

#### `(on-class-change #*args)`
Attaches <callback> to class changes on the current window.

#### `(on-icon-change #*args)`
Attaches <callback> to icon changes on the current window.

#### `(on-name-change #*args)`
Attaches <callback> to name changes on the current window.

#### `(set-monitor monitor-ref-or-direction [preserve-tiling False])`
Move window to monitor identified by `monitor-ref-or-direction`.
  `monitor-ref-or-direction` can be one of "left", "right",
  "up" or "down" relative to the current window's monitor
  (i.e. the one that has most of the window in it) or it can be
  the monitor's connector name as defined by Xrandr (ex: "DP1",
  "HDMI1", etc.
  If preserve-tiling is true, the tiling pattern last set
  for this window will be reapplied after moving it to the
  new monitor.
  Returns True if move was successful, False otherwise.

#### `(tile [v-pattern "*")`
Tile the current window according to v-pattern and h-pattern.
   Patterns are composed of the plus sign (+) which represents the window
   and underscores (_) which represent empty space.
   For example, a vertical pattern of _+_ means the window will be in the middle row of
   a screen divided into three sections. A horizontal pattern of + means that
   the window will take the whole screen horizontally.
   Frame defines what we tile relative to (see ref-frame in settings).

#### `(tile-at position)`
Tile the current window. `position` can be one of :
     - "last"          resume the last tiling pattern for this particular window
     - "left"          which is equivalent to `(tile "*"    "*_" )`
     - "right"         which is equivalent to `(tile "*"    "_*" )`
     - "top"           which is equivalent to `(tile "_*"   "*"  )`
     - "top-left"      which is equivalent to `(tile "_*"   "*_" )`
     - "top-right"     which is equivalent to `(tile "_*"   "_*" )`
     - "center"        which is equivalent to `(tile "_*_*" "__*")`
     - "center-left"   which is equivalent to `(tile "_*_*" "*_" )`
     - "center-right"  which is equivalent to `(tile "_*_*" "_*" )`
     - "bottom"        which is equivalent to `(tile "_*"   "*"  )`
     - "bottom-left"   which is equivalent to `(tile "_*"   "*_" )`
     - "bottom-right"  which is equivalent to `(tile "_*"   "_*" )`
     - "full"          which is equivalent to `(tile "*"    "*"  )`
   See the documentation for `tile` for more information.

#### `(tile-move direction)`
Move the current window in <direction> within
   its current tiling pattern.

#### `(screen-height )`
Returns the height in pixels of the current window's screen.

#### `(screen-width )`
Returns the width in pixels of the current window's screen.

#### `(unfullscreen )`
Make the current window not fullscreen, returns True.

#### `(window-index )`
Returns the index of the window in the taskbar.

#### `(window-index-in-class )`
Returns the index of the window in the taskbar, counting only the windows of the same class.

#### `(window-index-in-workspace )`
Returns the index of the window in the taskbar, counting only the windows of the same workspace.

#### `(window-type type)`
Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop.
