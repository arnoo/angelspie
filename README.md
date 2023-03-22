![Angelspie logo](https://github.com/arnoo/angelspie/blob/master/logo/readme_header.png?raw=true)

Angelspie is a tool to apply rules to windows on Linux: placement, workspace, tiling, decorations… based on window name, class, role…

Angelspie is intended as a drop-in replacement for Devilspie which is unmaintained and now segfaults way too often.

Compared to Devilspie, Angelspie has some added functionality for tiling and multi monitor setups. It also repositions windows when display configuration changes (monitor added or removed for instance).

If you start Angelspie and no configuration files exist, configuration files will be built based on your Devilspie config if you have one. 

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
  (unpin)
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

Grab a release and run the angelspie binary in a terminal window. Once you have your configuration files figured out, you might want to run angelspie on startup.

To run the dev version, clone the git repository then use `pipenv run hy angelspie.hy` in its root directory.

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


### Firefox

Angelspie combined with "I Hate Tabs - SDI extension" gives you Firefox with tiling windows instead of tabs.


### XFCE


This forces the XFCE workspace switcher to re-adjust to the new display geometry when unplugging a monitor.

```hy
(on-monitors-change
  (spawn-async "xfconf-query -c xfce4-panel -p /plugins/plugin-2/miniature-view -s false;
                xfconf-query -c xfce4-panel -p /plugins/plugin-2/miniature-view -s true"))
```



## API documentation
### DEVILSPIE FUNCTIONS/MACROS
#### `(application_name)`
Return the application name (as determined by libwnck) of the current window (String).

#### `(above)`
Set the current window to be above all normal windows, returns True.

#### `(begin #*forms)`
The devilspie equivalent of Hy's `do` : evaluates all the function calls within, returns the result of the last evaluation.

#### `(below)`
Set the current window to be below all normal windows, returns True.

#### `(center)`
Center position of current window, returns boolean.

#### `(close)`
Close the current window, returns True.

#### `(contains string substring)`
True if string contains substring.

#### `(debug)`
Debugging function, outputs the current window's title, name, role and geometry (Returns TRUE).

#### `(decorate)`
Add the window manager decorations to the current window, returns boolean.

#### `(dsif cond-clause then-clause [else-clause None])`
Equivalent to Devilspie's if. Like Hy's builtin if, but the else clause is optional.
   Evaluates then-clause if cond-clause is True, else-clause otherwise if provided.

#### `(dsprint #*args)`
Equivalent to Devilspie's print.
   Print args without trailing newline, returns boolean.

#### `(focus)`
Focus the current window, returns True.

#### `(fullscreen)`
Make the current window fullscreen, returns True.

#### `(geometry geom-str)`
Set position + size (as string) of current window, returns boolean.
   geom-str should be in X-GeometryString format:
    `[=][<width>{xX}<height>][{+-}<xoffset>{+-}<yoffset>]`
   as an extension to the X-GeometryString format, all values
   can be specified as percentages of screen/monitor size. For
   percentages of screen size, set setting "ref-frame" to RefFrame.SCREEN
   Examples:
       `(geometry "400×300+0-22")`
       `(geometry "640×480")`
       `(geometry "100%×50%+0+0")`
       `(geometry "+10%+10%")`

#### `(matches string pattern)`
True if the regexp pattern matches str

#### `(once #*forms)`
Eval forms only once in a given Angelspie session.
   Can be useful to, say, close a window once for a specific
   app.

#### `(once-per-window #*forms)`
Eval forms only once for each window in a given Angelspie session.
   Useful for example to focus newly created windows after they have
   changed workspace.

#### `(opacity level)`
Change the opacity level (as integer in 0..100) of the current window, returns boolean.

#### `(maximize)`
Maximise the current window, returns True.

#### `(maximize_vertically)`
Maximise vertically the current window, returns True.

#### `(maximize_horizontally)`
Maximise horizontally the current window, returns True.

#### `(minimize)`
Minimise the current window, returns True.

#### `(pin)`
Pin the current window to all workspaces, returns True.

#### `(println #*args)`
Print args with trailing newline, returns True.

#### `(set_viewport viewport-nb)`
Move the window to a specific viewport number, counting from 1, returns boolean.

#### `(set_workspace workspace-nb)`
Move the window to a specific workspace number, counting from 1, returns boolean.
   Note that moving a window to another workspace makes it lose focus. To keep new
   windows focused in all situations, you might want to add `(once-per-window (focus))`
   at the end of your Angelspie scripts.

#### `(shade)`
Shade ('roll up') the current window, returns True.

#### `(skip_pager [active True])`
Remove the current window from the window list, returns True.
   If passed `active=False`, puts the window back in the window list.

#### `(skip_tasklist [active True])`
Remove the current window from the pager, returns True.
   If passed `active=False`, puts the window back in the pager.

#### `(spawn_async #*cmd)`
Execute a command in the background, returns boolean. Command is given as a single string, or as a series of strings (similar to execl).

#### `(spawn_sync #*cmd)`
Execute  a  command in the foreground (returns command output as string, or `False` on error). Command is given as a single string, or as a series of strings (similar to execl).

#### `(stick)`
Make the current window stick to all viewports, returns True.

#### `(str+ #*args)`
Transform parameters into strings and concat them with spaces in between.

#### `(undecorate)`
Remove the window manager decorations from the current window, returns boolean.

#### `(unmaximize)`
Un-maximise the current window, returns True.

#### `(unminimize)`
Un-minimise the current window, returns True.

#### `(unpin)`
Unpin the current window from all workspaces, returns True.

#### `(unshade)`
Un-shade ('roll down') the current window, returns True.

#### `(unstick)`
Unstick the window from viewports, returns True.

#### `(wintype type)`
Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop.

#### `(window_class [prospective True])`
Return the class of the current window (String).
   If `prospective=True`, will return the class the window
   is expected to have soon due to a possible call to set-window-class.

#### `(window_name)`
Return the title of the current window (String).

#### `(window_property prop-name)`
Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String).

#### `(window_role)`
Return the role (as determined by the WM_WINDOW_ROLE hint) of the current window (String).

#### `(window_workspace [window None] [prospective True])`
Returns the workspace the current window is on (Integer).
   If `prospective=True` will return the workspace the window
   is on or is expected to be on soon due to a pending
   set-window-workspace call.

#### `(window_xid)`
Return the X11 window id of the current window (Integer).

### ADDITIONS TO DEVILSPIE
#### `(setting varname val-form)`
Set Angelspie setting <varname> to the result of evaluating val-form
   in each window/monitor/etc. context where the setting is needed.

#### `(browser-favicon [use-full-url False])`
None

#### `(browser-url)`
None

#### `(empty geom-str [workspace-nb None])`
Returns True if rectangle corresponding to geom-str is empty,
   i.e. no windows intersect the rectangle, on the workspace
   of the current window or on workspace number <workspace-nb>
   if specified. Returns False if there is an intersecting window.
   The current window is ignored, as are minimized windows.

#### `(monitor)`
Returns the connector name of the current window's monitor
   i.e. the one that has most of the window in it.

#### `(monitor-edid [connector-name None])`
Returns the EDID of the current monitor, or, if
   `connector-name` is supplied, of the corresponding
   monitor.
   Returns None if no matching monitor is found for
   connector-name.

#### `(monitor-connected connector-name [EDID None])`
Returns True if monitor with connector connector-name is connected, False otherwise.
   If EDID is supplied, returns True only if the monitor's EDID matches.
   To get the connector name for a monitor type `xrand` in your terminal.
   To get the EDID for a monitor use Angelspie function
   `(monitor-edid connector-name)`.

#### `(monitor-height)`
Returns the height in pixels of the current window's
   monitor, i.e. the one that has most of the window in it.

#### `(monitor-is-primary)`
Returns `True` if the current window's monitor,
   i.e. the one that has most of the window in it,
   is primary, `False` otherwise.

#### `(monitor-width)`
Returns the width in pixels of the current window's
   monitor, i.e. the one that has most of the window in it.

#### `(on-class-change #*forms)`
Runs <forms> on class changes of the current window.

#### `(on-icon-change #*forms)`
Runs <forms> on icon changes of the current window.

#### `(on-name-change #*forms)`
Runs <forms> on name changes of the current window.

#### `(on-monitors-change #*forms)`
Runs <forms> on changes in monitor setup.

#### `(set-monitor monitor-ref-or-direction [preserve-tiling False])`
Move window to monitor identified by `monitor-ref-or-direction`.
  `monitor-ref-or-direction` can be one of "left", "right",
  "up" or "down" relative to the current window's monitor
  (i.e. the one that has most of the window in it), "primary" for
  the primary monitor or it can be the monitor's connector name as
  defined by Xrandr (ex: "DP1", "HDMI1", etc.
  If preserve-tiling is true, the tiling pattern last set
  for this window will be reapplied after moving it to the
  new monitor.
  Returns `True` if move was successful, `False` otherwise.

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
     - "center"        which is equivalent to `(tile "_**_" "_**_")`
     - "center-left"   which is equivalent to `(tile "_**_" "*_" )`
     - "center-right"  which is equivalent to `(tile "_**_" "_*" )`
     - "bottom"        which is equivalent to `(tile "_*"   "*"  )`
     - "bottom-left"   which is equivalent to `(tile "_*"   "*_" )`
     - "bottom-right"  which is equivalent to `(tile "_*"   "_*" )`
     - "full"          which is equivalent to `(tile "*"    "*"  )`
   See the documentation for `tile` for more information.

#### `(tile-move direction)`
Move the current window in <direction> within
   its current tiling pattern.

#### `(set-window-class class)`
None

#### `(screen-height)`
Returns the height in pixels of the current window's screen.

#### `(screen-width)`
Returns the width in pixels of the current window's screen.

#### `(unfullscreen)`
Make the current window not fullscreen, returns True.

#### `(window-index)`
Returns the index of the window in the taskbar.

#### `(window-index-in-class)`
Returns the index of the window in the taskbar, counting only the windows of the same class.

#### `(window-index-in-workspace)`
Returns the index of the window in the taskbar, counting only the windows of the same workspace.

#### `(window-type type)`
Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop.

