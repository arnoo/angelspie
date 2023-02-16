; Copyright © 2023 Arnaud Bétrémieux <arnaud@btmx.fr>

; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <https://www.gnu.org/licenses/>.

; TODO: check https://sources.debian.org/src/devilspie/0.23-2/src/actions.c/
; And maybe use wnck as in original devilspie for missing functions and maybe others ?

(import argparse)
(import glob)
(import math)
(import os)
(import pathlib)
(import pywinctl :as pwc) ; In the hope of making things somewhat cross-platform, but does not provide much… will probably reconsider and use Xlib / wnck
(import re)
(import subprocess)
(import time)
(import Xlib)

(setv *disp* (Xlib.display.Display))
(setv +config-dir+ (os.path.join (pathlib.Path.home) ".config/angelspie"))

;; UTILS

(defn add-state-prop [prop]
  (spawn_async "wmctrl" "-i" "-r" (window_xid) "-b" (+ "add," prop)))

(defn remove-state-prop [prop]
  (spawn_async "wmctrl" "-i" "-r" (window_xid) "-b" (+ "remove," prop)))

(defn parse-command-line []
  (setv parser (argparse.ArgumentParser :description "Act on windows when created"))
  (.add-argument parser
                 "--eval"
                 :default []
                 :help "as code to eval. Disables loading of config files, happens after processing conf_file arguments."
                 :metavar "AS_CODE"
                 :nargs "*")
  (.add-argument parser
                 "--load"
                 :default []
                 :help "as script to run for each window (by default ~/.config/angelspie/*.as)"
                 :metavar "LOAD_FILE"
                 :nargs "*")
  (.parse-args parser))

(defn try-to-build-config-from-devilspie-if-we-have-none []
  (when (not (glob.glob (os.path.join +config-dir+ "*.as")))
    (os.mkdir +config-dir+)
    (for [ds-file (glob.glob (os.path.join (pathlib.Path.home) ".devilspie/*.ds"))]
      (print f"Importing config from '{ds-file}'")
      (with [ds-handle (open ds-file)]
        (setv script (ds-handle.read)))
      (setv script (script.replace "(if " "(dsif "))
      (setv script (script.replace "(is " "(= "))
      (setv script (script.replace "(str " "(str+ "))
      (setv script (script.replace "(print " "(dsprint "))
      (setv as-file (re.sub "\\.ds$" ".as" ds-file))
      (setv as-file (re.sub "^.*/\\.devilspie" (str +config-dir+) as-file))
      (with [as-handle (open as-file "w")]
        (as-handle.write script)))))

(defn str+ [#*args]
  "Transform parameters into strings and concat them with spaces in between."
  (. "" (join (list (map str args)))))

(defn screens-hash []
  (setv screens-dict (pwc.getAllScreens))
  (setv hash "")
  (for [key (screens-dict.keys)]
    (setv hash (str+ hash key (get (get screens-dict key) "size"))))
  hash)

(defn not-yet-implemented [fn-name]
  (print f"WARNING: Call to function '{fn-name}' which is not yet implemented."))

(defn window-xprop-value [prop_name]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  (setv xprop
        (*current-xwindow*.get_full_property
          (*disp*.intern_atom prop_name)
          Xlib.X.AnyPropertyType))
  (when xprop
    (. xprop.value [0])))

(defn dimension-to-pixels [dimension [is-vertical False]]
  (if (.endswith (str dimension) "%")
      (math.floor (/ (* (int (get (str dimension) (slice 0 -1)))
                        (if is-vertical (screen-height) (screen-width)))
                     100))
      (int dimension)))

;; DEVILSPIE FUNCTIONS/MACROS

(defmacro begin [&rest args]
  `(do ~args))

(defn application_name []
  "Return the application name (as determined by libwnck) of the current window (String)."
  (*current-window*.getAppName))

(defn above []
  "Set the current window to be above all normal windows , returns True."
  (*current-window*.alwaysOnTop)
  True)

(defn below []
  "Set the current window to be below all normal windows , returns True."
  (*current-window*.alwaysOnBottom)
  True)

(defn center []
  "Center position of current window , returns boolean."
  (not-yet-implemented "center"))

(defn close []
  "Close the current window , returns True."
  (*current-window*.close)
  True)

(defn contains [string substring]
  "True if string contains substring."
  (in substring string))

(defn debug []
  "Debugging function, outputs the current window's title, name, role and geometry (Returns TRUE)."
  (print f"Window Title: {(window_name)}; Application Name: '{(application_name)}'; Class: '{(window_class)}'; Geometry: {*current-window*.width}x{*current-window*.height}+{*current-window*.left}+{*current-window*.top}")
  True)

(defn decorate []
  "Add the window manager decorations to the current window , returns boolean."
  (*current-xwindow*.change_property
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    32
    [0x0 0x0 0x0 0x0 0x0]))

(defmacro dsif [cond-clause then-clause [else-clause None]]
  `(if ~cond-clause
       ~then-clause
       ~(when else-clause else-clause)))

(defmacro dsprint [#*args]
  "Print args without trailing newline, returns boolean."
  (print #*args :sep ""
                :end ""
                :flush True))

(defn focus []
  "Focus the current window , returns True."
  (*current-window*.activate)
  True)

(defn fullscreen []
  "Make the current window fullscreen , returns True."
  (add-state-prop "fullscreen")
  True)

(defn geometry [geom-str]
  "Set position + size (as string) of current window , returns boolean.
   geom-str should be in X-GeometryString format:
    [=][<width>{xX}<height>][{+-}<xoffset>{+-}<yoffset>]
   as an extension to the X-GeometryString format, all values
   can be specified as percentages of screen size.
   Note that negative positions are considered as 0
   by the underlying pywinctl library and therefore useless.
   Examples:
       (geometry \"400×300+0-22\")
       (geometry \"640×480\")
       (geometry \"100%×50%+0+0\")
       (geometry \"+10%+10%\")"
  (setv dim_re "\\d+\\%{0,1}")
  (setv size_re "[+-]\\d+\\%{0,1}")
  (setv geom-parts
        (re.match (+ "(=|)"
                     "((?P<w>" dim_re ")x(?P<h>" dim_re ")|)"
                     "((?P<x>" size_re ")(?P<y>" size_re ")|)"
                     "$")
                  (.lower geom-str)))
  (when (not geom-parts)
    (print f"Invalid geometry: {geom-str}")
    (return False))
  (when (.group geom-parts "w")
    (*current-window*.resizeTo (dimension-to-pixels (.group geom-parts "w"))
                               (dimension-to-pixels (.group geom-parts "h") :is-vertical True)))
  (when (.group geom-parts "x")
    (*current-window*.moveTo (dimension-to-pixels (.group geom-parts "x"))
                             (dimension-to-pixels (.group geom-parts "y") :is-vertical True))))

(defn matches [string pattern]
  "True if the regexp pattern matches str"
  (bool (re.search pattern string)))

(defn opacity [level]
  "Change the opacity level (as integer in 0..100) of the current window , returns boolean."
	;v=0xffffffff/100*level;
	;XChangeProperty (gdk_x11_get_default_xdisplay (), wnck_window_get_xid(c->window),
	;	my_wnck_atom_get ("_NET_WM_WINDOW_OPACITY"),
	;	XA_CARDINAL, 32, PropModeReplace, (guchar *)&v, 1);
  (not-yet-implemented "opacity"))

(defn maximize []
  "Maximise the current window , returns True."
  (*current-window*.maximize)
  True)

(defn maximize_vertically []
  "Maximise vertically the current window , returns True."
  (add-state-prop "maximized_vert")
  True)

(defn maximize_horizontally []
  "Maximise horizontally the current window , returns True."
  (add-state-prop "maximized_horz")
  True)

(defn minimize []
  "Minimise the current window , returns True."
  (*current-window*.minimize)
  True)

(defn pin []
  "Pin the current window to all workspaces , returns True."
  (add-state-prop "sticky")
  True)

(defn println [#*args]
  "Print args with trailing newline, returns True."
  (print #*args
         :sep "")
  True)

(defn set_viewport [viewport-nb]
  "Move the window to a specific viewport number, counting from 1 , returns boolean."
  (not-yet-implemented "set_viewport"))

(defn set_workspace [workspace-nb]
  "Move the window to a specific workspace number, counting from 1 , returns boolean."
  ;(*current-xwindow*.change_property
  ;  (*disp*.intern_atom "_NET_WM_DESKTOP")
  ;  Xlib.Xatom.CARDINAL
  ;  32
  ;  [(- workspace-nb 1) 0x0 0x0 0x0]))
  (spawn_async "wmctrl" "-i" "-r" (window_xid) "-t" (- workspace-nb 1)))

(defn shade []
  "Shade ('roll up') the current window , returns True."
  (add-state-prop "shaded")
  True)

(defn skip_pager []
  "Remove the current window from the window list , returns True."
  (add-state-prop "skip_pager")
  True)

(defn skip_tasklist []
  "Remove the current window from the pager , returns True."
  (add-state-prop "skip_taskbar")
  True)

(defn spawn_async [#*cmd]
  "Execute a command in the background , returns boolean. Command is given as a single string, or as a series of strings (similar to execl)."
  (setv string-cmd (.join " " (map str cmd)))
  (print "spawn_async" string-cmd)
  (subprocess.Popen ["bash" "-c" string-cmd]))

(defn spawn_sync [#*cmd]
  "Execute  a  command in the foreground (returns command output as string, or FALSE on error). Command is given as a single string, or as a series of strings (similar to execl)."
  (setv string-cmd (.join " " (map str cmd)))
  (print "spawn" string-cmd)
  (.decode (. (subprocess.run ["bash" "-c" string-cmd] :stdout subprocess.PIPE)
              stdout)
           "utf-8"))

(defn stick []
  "Make the current window stick to all viewports , returns True."
  (not-yet-implemented "stick"))

(defn undecorate []
  "Remove the window manager decorations from the current window , returns boolean."
  (*current-xwindow*.change_property
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    32
    [0x2 0x0 0x0 0x0 0x0]))

(defn unmaximize []
  "Un-maximise the current window , returns True."
  (remove-state-prop "maximized_vert,maximized_horz")
  True)

(defn unminimize []
  "Un-minimise the current window , returns True."
  (*current-window*.restore)
  True)

(defn unpin []
  "Unpin the current window from all workspaces , returns True."
  (remove-state-prop "sticky")
  True)

(defn unshade []
  "Un-shade ('roll down') the current window , returns True."
  (remove-state-prop "shaded")
  True)

(defn unstick []
  "Unstick the window from viewports , returns True."
  (not-yet-implemented "unstick")
  True)

(defn wintype [type]
  "Set the window type of the current window , returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop."
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
  (when xprop-value
    (*disp*.get_atom_name xprop-value)))

(defn window_role []
  "Return the role (as determined by the WM_WINDOW_ROLE hint) of the current window (String)."
  (not-yet-implemented "window_role"))

(defn window_workspace []
  "Returns the workspace a window is on (Integer)."
  (+ (window-xprop-value "_NET_WM_DESKTOP") 1))

(defn window_xid []
  "Return the X11 window id of the current window (Integer)."
  *current-xwindow*.id)

;; ADDITIONS TO DEVILSPIE

(defn tile [direction [screen-margin-top 0]
                      [screen-margin-bottom 0]
                      [screen-margin-left 0]
                      [screen-margin-right 0]
                      [window-margin-horizontal 0]
                      [window-margin-vertical 0]]
  (unmaximize)
  (setv x screen-margin-left)
  (setv y screen-margin-top)
  (setv w (- (screen_width)
             (dimension-to-pixels screen-margin-right)
             (dimension-to-pixels screen-margin-left)))
  (setv h (- (screen_height)
             (dimension-to-pixels screen-margin-top :is-vertical True)
             (dimension-to-pixels screen-margin-bottom :is-vertical True)))
  (when (in "left" direction)
    (setv x screen-margin-left))
  (when (in "right" direction)
    (setv x (+ (dimension-to-pixels "50%")
               (math.floor (/ (dimension-to-pixels window-margin-horizontal) 2)))))
  (when (or (in "left" direction)
            (in "right" direction))
    (setv w (math.floor (- (/ w 2)
                           (/ (dimension-to-pixels window-margin-horizontal) 2)))))
  (when (in "bottom" direction)
    (setv y (- (dimension-to-pixels "50%" :is-vertical True)
               (dimension-to-pixels screen-margin-bottom :is-vertical True)
               (math.floor (/ (dimension-to-pixels window-margin-vertical :is-vertical True) 2)))))
  (when (in "top" direction)
    (setv y screen-margin-top))
  (when (in "center" direction)
    (setv y "25%")
    (setv h "45%"))
  (when (or (in "bottom" direction)
            (in "top" direction))
    (setv h (math.floor (- (/ h 2)
                           (/ (dimension-to-pixels window-margin-vertical) 2)))))
  ; (print "TILE " (.join "" [(str x) "x" (str y) "+" (str w) "+" (str h)]))
  (*current-window*.resizeTo (dimension-to-pixels w)
                             (dimension-to-pixels h :is-vertical True))
  (*current-window*.moveTo (dimension-to-pixels x)
                           (dimension-to-pixels y :is-vertical True)))

(defn screen_height []
  (setv screen-size (pwc.getScreenSize (*current-window*.getDisplay)))
  screen-size.height)

(defn screen_width []
  (setv screen-size (pwc.getScreenSize (*current-window*.getDisplay)))
  screen-size.width)

(defn unfullscreen []
  "Make the current window fullscreen , returns True."
  (remove-state-prop "fullscreen")
  True)
  
(defn window-index-in-class []
  (setv index 0)
  (for [w (sorted (pwc.getAllWindows) :key (fn [ww] (str (ww.getHandle))))]
     (when (= (. (.get_wm_class (w.getHandle)) [1])
              (window_class))
       (when (= (w.getHandle) *current-xwindow*)
         (break))
       (setv index (+ index 1))))
  index)

(defn window-type [type]
  "Set the window type of the current window , returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop."
  (wintype type))

;; MAIN

(defn process-window [window]
  (global *current-window*)
  (global *current-xwindow*)
  (setv *current-window* window)
  (setv *current-xwindow* (window.getHandle))
  (try
    (for [as-file (if (or *command-line-args*.load *command-line-args*.eval)
                      *command-line-args*.load
                      (sorted (glob.glob (os.path.join +config-dir+ "*.as"))))]
      (print "== Running" as-file)
      (hy.eval (hy.read-many (open as-file))))
    (for [eval-str *command-line-args*.eval]
      (hy.eval (hy.read-many eval-str)))
    (except [e [Xlib.error.BadDrawable Xlib.error.BadWindow]]
      (print "Window closed during script execution")
      (return False))))


(defn main-loop []
  (try-to-build-config-from-devilspie-if-we-have-none)
  (when (and (not (glob.glob (os.path.join +config-dir+ "*.as")))
             (not *command-line-args*.load))
    (print "No configuration file found and none specified in command-line")
    (return))
  (setv *last-screens-hash* "")
  (while True
    (setv new-screens-hash (screens-hash))
    (when (not (= new-screens-hash *last-screens-hash*))
      (when (not (= *last-screens-hash* ""))
        (print "Screen configuration changed, rerunning configuration scripts for all windows"))
      (setv *last-screens-hash* new-screens-hash)
      (setv *known-xwindows* {}))
    (for [w (*known-xwindows*.keys)]
      (setv (. *known-xwindows* [w]) False))
    (for [window (pwc.getAllWindows)]
      (when (not (in (window.getHandle) *known-xwindows*))
        (process-window window))
      (setv (. *known-xwindows* [(window.getHandle)]) True))
    (for [w (list (*known-xwindows*.keys))]
       (when (not (. *known-xwindows* [w]))
          (del (. *known-xwindows* [w]))))
    (time.sleep 0.2)))

(setv *command-line-args* (parse-command-line))
(if *command-line-args*.eval
  (process-window (pwc.getActiveWindow))
  (main-loop))
