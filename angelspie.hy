; NOTE THAT YOU WILL NEED TO REPLACE (if with (when in YOUR .ds files and (str with (concat, and (is with (=
(import subprocess)
(import pywinctl :as pwc)
(import time)

(defn not-yet-implemented [fn-name]
  (print f"WARNING: Call to function '{fn-name}' which is not yet implemented."))

(defmacro begin [&rest args]
  `(do ~args))

(defn below []
  (pwc.lowerWindow *current-window*))

(defn close []
  "Close the current window (returns TRUE)."
  (pwc.close *current-window*))

(defn contains [string substring]
  "True if string contains substring."
  (in substring string))

(defn matches [string pattern]
  "True if the regexp pattern matches str"
  (not-yet-implemented "matches"))

(defn focus []
  "Focus the current window (returns TRUE)."
  (*current-window*.activate))

(defn geometry [geom-str]
  "Set position + size (as string) of current window (returns boolean)."
  (if (in "+" geom-str)
    (do (setv parts (geom-str.split "+"))
        (setv size (. parts [0]))
        (setv pos (. parts [1])))
    (setv size geom-str))
  (setv [width height] (geom-str.split "x"))
  (pwc.resizeTo *current-window* width height)
  (when pos
    (setv [x y] (pos.split "+"))
    (pwc.moveTo *current-window* x y)))

(defn is [a b]
  "String equality, (is a b) means a is the same as b."
  (== a b))

(defn set_workspace [workspace-nb]
  "Move the window to a specific workspace number, counting from 1 (returns boolean)."
  (spawn_async (concat "wmctrl -i -r " (window_xid) " -t " (- workspace-nb 1))))

(defn add_state_prop [prop]
  (spawn_async (concat "wmctrl -i -r " (window_xid) " -b add " prop)))

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
  (. (subprocess.run ["bash" "-c" (concat #*cmd)] stdout=subprocess.PIPE) stdout))

(defn concat [#*args]
  "Transform parameters into strings and concat them."
  (. " " (join (list (map str args)))))

(defn undecorate []
  "Remove the window manager decorations from the current window (returns boolean)."
  (spawn_async (concat "xprop -id " (window_xid) " -format _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS 2")))

(defn window_class []
  "Return the class of the current window (String)."
  (. (*current-xwindow*.get_wm_class) [0]))

(defn window_name []
  "Return the title of the current window (String)."
  (str (*current-xwindow*.get_wm_name)))

(defn window_property [prop]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  ; "_NET_WM_WINDOW_TYPE "
;  (*current-xwindow*.get_property prop "String" 0 32))
  (not-yet-implemented "window_property"))

(defn window_xid []
  "Return the X11 window id of the current window (Integer)."
  *current-xwindow*.id)

(defn wintype [type]
  "Set the window type of the current window (returns boolean). Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop."
  (not-yet-implemented "wintype"))

(defn println [str]
  "Print args (with trailing 0 returns boolean)."
  (not-yet-implemented "println"))

(defn window_role []
  "Return the role (as determined by the WM_WINDOW_ROLE hint) of the current window (String)."
  (not-yet-implemented "window_role"))

(defn application_name []
  "Return the application name (as determined by libwnck) of the current window (String)."
  (not-yet-implemented "application_name"))

(defn window_workspace []
  "Returns the workspace a window is on (Integer)."
  (not-yet-implemented "window_workspace"))

(defn debug []
  "Debugging function, outputs the current window's title, name, role and geometry (Returns TRUE)."
  (not-yet-implemented "debug"))

(defn hex []
  "Transform the integer parameter into an unsigned hexadecimal string (with 0x prefix)."
  (not-yet-implemented "hex"))

(defn skip_pager []
  "Remove the current window from the window list (returns TRUE)."
  (not-yet-implemented "skip_pager"))

(defn above []
  "Set the current window to be above all normal windows (returns TRUE)."
  (not-yet-implemented "above"))

(defn below []
  "Set the current window to be below all normal windows (returns TRUE)."
  (not-yet-implemented "below"))

(defn decorate []
  "Add the window manager decorations to the current window (returns boolean)."
  (not-yet-implemented "decorate"))

(defn opacity []
  "Change the opacity level (as integer in 0..100) of the current window (returns boolean)."
  (not-yet-implemented "opacity"))

(defn stick []
  "Make the current window stick to all viewports (returns TRUE)."
  (not-yet-implemented "stick"))

(defn unstick []
  "Unstick the window from viewports (returns TRUE)."
  (not-yet-implemented "unstick"))

(defn minimize []
  "Minimise the current window (returns TRUE)."
  (not-yet-implemented "minimize"))

(defn unminimize []
  "Un-minimise the current window (returns TRUE)."
  (not-yet-implemented "unminimize"))

(defn shade []
  "Shade ('roll up') the current window (returns TRUE)."
  (not-yet-implemented "shade"))

(defn unshade []
  "Un-shade ('roll down') the current window (returns TRUE)."
  (not-yet-implemented "unshade"))

(defn center []
  "enter position of current window (returns boolean)."
  (not-yet-implemented "center"))

(defn maximize []
  "Maximise the current window (returns TRUE)."
  (not-yet-implemented "maximize"))

(defn maximize_vertically []
  "Maximise vertically the current window (returns TRUE)."
  (not-yet-implemented "maximize_vertically"))

(defn maximize_horizontally []
  "Maximise horizontally the current window (returns TRUE)."
  (not-yet-implemented "maximize_horizontally"))

(defn unmaximize []
  "Un-maximise the current window (returns TRUE)."
  (not-yet-implemented "unmaximize"))

(defn pin []
  "Pin the current window to all workspaces (returns TRUE)."
  (not-yet-implemented "pin"))

(defn unpin []
  "Unpin the current window from all workspaces (returns TRUE)."
  (not-yet-implemented "unpin"))

(defn fullscreen []
  "Make the current window fullscreen (returns TRUE)."
  (not-yet-implemented "fullscreen"))

(defn set_viewport []
  "Move the window to a specific viewport number, counting from 1 (returns boolean)."
  (not-yet-implemented "set_viewport"))

(setv *known-xwindows* {})

(while True
  (for [window (pwc.getAllWindows)]
    (setv *current-window* window)
    (setv *current-xwindow* (window.getHandle))
    (when (not (in *current-xwindow* *known-xwindows*))
    ; (import pprint)
    ; (pprint.pprint (dir *current-window*))
    ; (pprint.pprint (dir *current-xwindow*))
      (print "window_name:" (window_name))
      (print "window_class:" (window_class))
      (hy.eval (hy.read-many (open "/home/arno/.devilspie/arno_new.ds")))
      (setv (. *known-xwindows* [*current-xwindow*]) True)))
  (time.sleep 0.1))
