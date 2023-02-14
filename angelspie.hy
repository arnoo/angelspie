(import pywinctl :as pwc)
(import subprocess)
(import time)
(import Xlib)

(setv *disp* (Xlib.display.Display))

;; UTILS

(defn add_state_prop [prop]
  (spawn_async (concat "wmctrl -i -r " (window_xid) " -b add " prop)))

(defn concat [#*args]
  "Transform parameters into strings and concat them."
  (. " " (join (list (map str args)))))

(defn not-yet-implemented [fn-name]
  (print f"WARNING: Call to function '{fn-name}' which is not yet implemented."))

(defn window-xprop-value [prop_name]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  (setv xprop
        (*current-xwindow*.get_full_property
          (*disp*.intern_atom prop_name)
          Xlib.X.AnyPropertyType))
  (. xprop.value [0]))

;; DEVILSPIE FUNCTIONS/MACROS

(defmacro begin [&rest args]
  `(do ~args))

(defn application_name []
  "Return the application name (as determined by libwnck) of the current window (String)."
  (*current-window*.getAppName))

(defn above []
  "Set the current window to be above all normal windows (returns TRUE)."
  (*current-window*.alwaysOnTop))

(defn below []
  "Set the current window to be below all normal windows (returns TRUE)."
  (*current-window*.alwaysOnBottom))

(defn center []
  "Center position of current window (returns boolean)."
  (not-yet-implemented "center"))

(defn close []
  "Close the current window (returns TRUE)."
  (*current-window*close))

(defn contains [string substring]
  "True if string contains substring."
  (in substring string))

(defn debug []
  "Debugging function, outputs the current window's title, name, role and geometry (Returns TRUE)."
  (print f"Window Title: {(window_name)}; Application Name: '{(application_name)}'; Class: '{(window_class)}'; Geometry: {*current-window*.width}x{*current-window*.height}+{*current-window*.left}+{*current-window*.top}"))

(defn decorate []
  "Add the window manager decorations to the current window (returns boolean)."
  (not-yet-implemented "decorate"))

(defn focus []
  "Focus the current window (returns TRUE)."
  (*current-window*.activate))

(defn fullscreen []
  "Make the current window fullscreen (returns TRUE)."
  (not-yet-implemented "fullscreen"))

(defn geometry [geom-str]
  "Set position + size (as string) of current window (returns boolean)."
  (if (in "+" geom-str)
    (do (setv parts (geom-str.split "+"))
        (setv size (. parts [0]))
        (setv pos (. parts [1])))
    (setv size geom-str))
  (setv [width height] (geom-str.split "x"))
  (*current-window*.resizeTo width height)
  (when pos
    (setv [x y] (pos.split "+"))
    (*current-window*.moveTo x y)))

(defn matches [string pattern]
  "True if the regexp pattern matches str"
  (not-yet-implemented "matches"))

(defn opacity [level]
  "Change the opacity level (as integer in 0..100) of the current window (returns boolean)."
  (not-yet-implemented "opacity"))

(defn maximize []
  "Maximise the current window (returns TRUE)."
  (*current-window*.maximize))

(defn maximize_vertically []
  "Maximise vertically the current window (returns TRUE)."
  (not-yet-implemented "maximize_vertically"))

(defn maximize_horizontally []
  "Maximise horizontally the current window (returns TRUE)."
  (not-yet-implemented "maximize_horizontally"))

(defn minimize []
  "Minimise the current window (returns TRUE)."
  (*current-window*.minimize))

(defn pin []
  "Pin the current window to all workspaces (returns TRUE)."
  (not-yet-implemented "pin"))

(defn set_viewport [viewport-nb]
  "Move the window to a specific viewport number, counting from 1 (returns boolean)."
  (not-yet-implemented "set_viewport"))

(defn set_workspace [workspace-nb]
  "Move the window to a specific workspace number, counting from 1 (returns boolean)."
  (*current-xwindow*.change_property
    (*disp*.intern_atom "_NET_WM_DESKTOP")
    Xlib.Xatom.CARDINAL
    32
    [(- workspace-nb 1) 0x0 0x0 0x0]))

(defn shade []
  "Shade ('roll up') the current window (returns TRUE)."
  (not-yet-implemented "shade"))

(defn skip_pager []
  "Remove the current window from the window list (returns TRUE)."
  (not-yet-implemented "skip_pager"))

(defn skip_tasklist []
  "Remove the current window from the pager (returns TRUE)."
  (add_state_prop "skip_taskbar"))

(defn spawn_async [#*cmd]
  "Execute a command in the background (returns boolean). Command is given as a single string, or as a series of strings (similar to execl)."
  (print "SPAWN ASYNC" (concat #*cmd))
  (subprocess.Popen ["bash" "-c" (concat #*cmd)]))

(defn spawn_sync [#*cmd]
  "Execute  a  command in the foreground (returns command output as string, or FALSE on error). Command is given as a single string, or as a series of strings (similar to execl)."
  (print "SPAWN" (concat #*cmd))
  (. (subprocess.run ["bash" "-c" (concat #*cmd)] :stdout subprocess.PIPE) stdout))

(defn stick []
  "Make the current window stick to all viewports (returns TRUE)."
  (not-yet-implemented "stick"))

(defn undecorate []
  "Remove the window manager decorations from the current window (returns boolean)."
  (*current-xwindow*.change_property
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    32
    [0x2 0x0 0x0 0x0 0x0]))

(defn unmaximize []
  "Un-maximise the current window (returns TRUE)."
  (not-yet-implemented "unmaximize"))

(defn unminimize []
  "Un-minimise the current window (returns TRUE)."
  (not-yet-implemented "unminimize"))

(defn unpin []
  "Unpin the current window from all workspaces (returns TRUE)."
  (not-yet-implemented "unpin"))

(defn unshade []
  "Un-shade ('roll down') the current window (returns TRUE)."
  (not-yet-implemented "unshade"))

(defn unstick []
  "Unstick the window from viewports (returns TRUE)."
  (not-yet-implemented "unstick"))

(defn wintype [type]
  "Set the window type of the current window (returns boolean). Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop."
  (not-yet-implemented "wintype"))

(defn window_class []
  "Return the class of the current window (String)."
  (. (*current-xwindow*.get_wm_class) [1]))

(defn window_name []
  "Return the title of the current window (String)."
  (str (*current-xwindow*.get_wm_name)))

(defn window_property [prop-name]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  (setv xprop-value (window-xprop-value prop-name))
  (*disp*.get_atom_name xprop-value))

(defn window_role []
  "Return the role (as determined by the WM_WINDOW_ROLE hint) of the current window (String)."
  ;(*current-xwindow*.get_wm_hints)
  (not-yet-implemented "window_role"))

(defn window_workspace []
  "Returns the workspace a window is on (Integer)."
  (window-xprop-value "_NET_WM_DESKTOP"))

(defn window_xid []
  "Return the X11 window id of the current window (Integer)."
  *current-xwindow*.id)

;; MAIN LOOP

(setv *known-xwindows* {})

(while True
  (for [window (pwc.getAllWindows)]
    (setv *current-window* window)
    (setv *current-xwindow* (window.getHandle))
    (when (not (in *current-xwindow* *known-xwindows*))
    ; (import pprint)
    ; (pprint.pprint (dir *current-window*))
    ; (pprint.pprint (dir *current-xwindow*))
    ; (pprint.pprint (*current-xwindow*.get_wm_hints))
      (debug)
      (print (window_property "_NET_WM_WINDOW_TYPE"))
      (hy.eval (hy.read-many (open "/home/arno/.devilspie/arno_new.ds")))
      (setv (. *known-xwindows* [*current-xwindow*]) True)))
  (time.sleep 0.1))
