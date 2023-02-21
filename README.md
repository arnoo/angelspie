Angelspie is a tool to apply rules to windows on Linux: placement, workspace, tiling, decorations… based on window name, class, role…

Angelspie is intended as a drop-in replacement for Devilspie which is unmaintained and now segfaults way too often.

Compared to Devilspie, Angelspie has some added functionality for tiling. It also repositions windows when display configuration changes (screen added or removed for instance).

If you start Angelspie and no configuration files exist, it will build configuration files based on your Devilspie config if you have one. 

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

In `.as` files, there are a few changes from Devilspie syntax made to avoid ugly redefinitions of hy/python reserved words:
- `if` has been renamed `dsif` (for Devilspie `if`). The difference with hy's builtin `if` is that the else clause is optional in `dsif`
- `is` is removed in favor of hy/python's built-in `=`
- `print` has been renamed `dsprint`
- `str` has been renamed `str+`

The following Devilspie functions are as of yet unimplemented:
- `center`
- `opacity`
- `set_viewport`
- `stick`
- `unstick`
- `wintype`
- `window_role`

 You'll get a warning when your configuration script calls an undefined function. I welcome pull requests in the hope of making this at some point a complete drop-in replacement for Devilspie.


## Running

To run, use `pipenv run hy angelspie.hy` in the source directory.

## Command line use

You can specify `.as` scripts or even code for Angelspie to evaluate.

Code passed to `--eval` is evaluated in the context of the active window.

For example, I have this bound to Super+Right in my desktop environment:
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
          :screen-margin-top 34 
          :screen-margin-bottom 0
          :screen-margin-left 0
          :screen-margin-right 0
          :window-margin-horizontal 0
          :window-margin-vertical 0)))
```

It is loaded both in my keyboard shortcuts and as part of my global Angelspie configuration. This makes tiling adapt to the screen size and work exactly the same at the keyboard and in my Angelspie rules.

## API documentation

### DEVILSPIE FUNCTIONS/MACROS
#### `(application_name )`
Return the application name (as determined by libwnck) of the current window (String).

#### `(above )`
Set the current window to be above all normal windows, returns True.

#### `(begin &rest args)`
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
   can be specified as percentages of screen size.
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

#### `(skip_pager )`
Remove the current window from the window list, returns True.

#### `(skip_tasklist )`
Remove the current window from the pager, returns True.

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
#### `(tile direction [screen-margin-top 0)`
Tile the current window. `direction` can be one of :
     - "left"
     - "right"
     - "top"
     - "top-left"
     - "top-right"
     - "center"
     - "center-left"
     - "center-right"
     - "bottom"
     - "bottom-left"
     - "bottom-right"
     - "full"

#### `(screen_height )`
Returns whe height in pixels of the current window's screen.

#### `(screen_width )`
Returns whe width in pixels of the current window's screen.

#### `(unfullscreen )`
Make the current window fullscreen, returns True.

#### `(window-index )`
Returns the index of the window in the taskbar.

#### `(window-index-in-class )`
Returns the index of the window in the taskbar, counting only the windows of the same class.

#### `(window-index-in-workspace )`
Returns the index of the window in the taskbar, counting only the windows of the same workspace.

#### `(window-type type)`
Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop.
