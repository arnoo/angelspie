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

(import argparse)
(import enum [Enum])
(import glob)
(import math)
(import os)
(import pathlib)
(import pgi)
(pgi.require_version "GdkX11" "3.0")
(pgi.require_version "Gtk" "3.0")
(pgi.require_version "Wnck" "3.0")
(import pgi.repository [GdkX11 GLib Gtk Wnck])
(import re)
(import shelve)
(import signal)
(import subprocess)
(import sys)
(import threading)
(import time)
(import Xlib)
(import Xlib.display)
(import Xlib.ext [randr])
(require hyrule *)

(setv *disp* (Xlib.display.Display))
(setv *gdk-disp* (GdkX11.X11Display.get_default))
(setv +config-dir+ (os.path.join (pathlib.Path.home) ".config/angelspie"))
(setv +last-pattern-shelve+ (os.path.join +config-dir+ "tile_patterns.shelve"))

;; UTILS

(defmacro _with-window [window #*forms]
  `(do (global *current-window*
               *current-xwindow*
               *current-gdk-window*)
       (setv *current-window* ~window)
       (setv *current-xwindow* (*disp*.create_resource_object "window" (. ~window (get_xid))))
       (setv *current-gdk-window* (GdkX11.X11Window.foreign_new_for_display *gdk-disp* (. ~window (get_xid))))
       (*gdk-disp*.error_trap_push)
       (try ~forms
            (except [e [Xlib.error.BadDrawable Xlib.error.BadWindow]]
               (_print-when-verbose "Window closed during script execution")
               (return False)))
       (ap-when (*gdk-disp*.error_trap_pop)
         (print "GDK ERROR" it)
         (return False))))

(setv _*window-callbacks*
      {
        "class-changed" {} 
        "name-changed" {}
        "icon-changed" {}
      })

(defn _attach_to_window_event [event-name callback]
  (unless (and (in (window_xid)
                   (get _*window-callbacks* event-name))
               (in callback
                   (get _*window-callbacks* event-name)))
    (*current-window*.connect event-name
                              (fn [win] (_with-window win (callback))))
    (assoc _*window-callbacks* event-name
           (if (in (window_xid)
                   (get _*window-callbacks* event-name))
                (+ (get _*window-callbacks* event-name) [callback])
                [callback]))))
  
(defn _docs []
  "Returns the API docs as Markdown"
  (with [source-handle (open (os.path.abspath __file__))]
    (for [line (source-handle.readlines)]
      (when (or (line.startswith "(defn")
                (line.startswith "(defmacro"))
        (setv [_ func-name func-args] (line.split " " 2))
        (unless (func-name.startswith "_")
          (setv func-args
            (if (= func-args "[]")
                ""
                (+ " " (cut func-args 1 -2))))
          (print f"#### `({func-name}{func-args})`")
          (if (line.startswith "(defn")
              (print (. (globals) [(hy.mangle func-name)] __doc__))
              (print (. __macros__ [(hy.mangle func-name)] __doc__)))
          (print)))
      (when (line.startswith "; ###")
        (print (cut line 2 -1))))))

(defn _dimension-to-pixels [dimension ref-dimension-px]
  (if (.endswith (str dimension) "%")
      (math.floor (/ (* (int (cut (str dimension) 0 -1))
                        ref-dimension-px)
                     100))
      (int dimension)))

(defn _get-geometry []
  "Return the current window's geometry in the
   context of the ref_frame set in settings."
  (setv [x y w h] (*current-window*.get-geometry))
  (when (= (_getsetting "ref-frame")
           RefFrame.MONITOR)
    (setv monitor-geom
          (. (_get-monitor)
            (get_geometry)))
    (setv x (- x (. monitor-geom x)))
    (setv y (- y (. monitor-geom y))))
  [x y w h])

(defn _get-xmonitor-by-connector-name [connector-name]
  ;TODO ability to filter by EDID : = XInternAtom (disp, RR_PROPERTY_RANDR_EDID, FALSE);
  ; so that we can use (monitor-connected "DP1" :edid "XXXXXXXXX")
  (for [m (. *disp*
             (screen)
             root
             (xrandr_get_monitors)
             monitors)]
     (when (= (. *disp* (get_atom_name m.name))
              connector-name)
       (return m))))

(defn _get-monitor [[monitor-ref-or-direction None]]
  (setv current-monitor (*gdk-disp*.get_monitor_at_window *current-gdk-window*))
  (unless monitor-ref-or-direction
    (return current-monitor))
  (setv current-geom (. current-monitor (get_geometry)))
  (setv ref-point
    (case monitor-ref-or-direction
      "left" [(- (. current-geom x) 1)
              (+ (. current-geom y) 1)]
      "right" [(+ (. current-geom x) (. current-geom width) 1)
               (+ (. current-geom y) 1)]
      "up" [(+ (. current-geom x) 1)
            (- (. current-geom y) 1)]
      "down" [(+ (. current-geom x) 1)
              (+ (. current-geom y) (. current-geom height) 1)]
      else  (ap-if (_get-xmonitor-by-connector-name monitor-ref-or-direction)
                [(+ (. it ["x"]) 1) (+ (. it ["y"]) 1)]
                (do (print f"Invalid monitor ref or direction: '{monitor-ref-or-direction}'")
                    (return None)))))
  (setv target-monitor (*gdk-disp*.get_monitor_at_point (get ref-point 0) (get ref-point 1)))
  (when (and (in monitor-ref-or-direction ["left" "right" "up" "down"])
             (= target-monitor current-monitor))
    ; *gdk-disp*.get_monitor_at_point returns the closest monitor
    ;  when point is outside any monitor
    (return None))
  target-monitor)

(defn _hdimension-to-pixels [dimension]
  (_dimension-to-pixels dimension
                        (if (= (_getsetting "ref-frame") RefFrame.SCREEN)
                            (screen-width)
                            (monitor-width))))

(defn _vdimension-to-pixels [dimension]
  (_dimension-to-pixels dimension
                        (if (= (_getsetting "ref-frame") RefFrame.SCREEN)
                            (screen-height)
                            (monitor-height))))

(defmacro _insist-on-geometry [#*forms]
  "Eval forms a few times… intended to call wnck move/resize twice,
   as wnck move/resize seems to often apply only internally but not onscreen."
  `(for [_ (range 1)]
     (do
       ~forms
       ;Calling get_geometry after resize/move seems necessary for some reason
       (*current-gdk-window*.get_geometry))))

(defn _is-valid-tile-pattern [pattern]
  (bool (re.match "^_*[*]+_*$" pattern)))

(defn _parse-command-line []
  (setv parser (argparse.ArgumentParser :description "Act on windows when created"))
  (parser.add-argument 
                 "--docs"
                 :action "store_const"
                 :const True
                 :help "Output the Markdown API docs and exit.")
  (parser.add-argument 
                 "--eval"
                 :default []
                 :help "as code to eval. Disables loading of config files, happens after processing conf_file arguments."
                 :metavar "AS_CODE"
                 :nargs "*")
  (parser.add-argument 
                 "-v"
                  "--verbose"
                 :action "store_const"
                 :const True
                 :help "Verbose output")
  (parser.add-argument
                 "--load"
                 :default []
                 :help "as script to run for each window (by default ~/.config/angelspie/*.as)"
                 :metavar "LOAD_FILE"
                 :nargs "*")
  (parser.parse-args))

(defn _print-when-verbose [#*args]
  (when *command-line-args*.verbose
     (print #*args)))

(defn _not-yet-implemented [fn-name]
  (print f"WARNING: Call to function '{fn-name}' which is not yet implemented."))

(defn _tile-inc-pattern [pattern increment]
  (if (> increment 0)
    (if (pattern.endswith "*")
        pattern
        (+ "_" (cut pattern 1 -1)))
    (if (pattern.startswith "*")
        pattern
        (+ (cut pattern 0 -2) "_"))))

(defn _try-to-build-config-from-devilspie-if-we-have-none []
  (unless (glob.glob (os.path.join +config-dir+ "*.as"))
    (os.mkdir +config-dir+)
    (for [ds-file (glob.glob (os.path.join (pathlib.Path.home) ".devilspie/*.ds"))]
      (print f"Importing config from '{ds-file}'")
      (with [ds-handle (open ds-file)]
        (setv script (ds-handle.read)))
      (doto script
            (.replace "(if " "(dsif ")
            (.replace "(is " "(= ")
            (.replace "(str " "(str+ ")
            (.replace "(print " "(dsprint "))
      (setv as-file (re.sub "\\.ds$" ".as" ds-file))
      (setv as-file (re.sub "^.*/\\.devilspie" (str +config-dir+) as-file))
      (with [as-handle (open as-file "w")]
        (as-handle.write script)))))

(defn _window-prospective-workspace [wnck-window]
  "Returns the workspace a window is in or is expected to be in soon due to a call to set_workspace."
  (ap-when (hasattr wnck-window "_angelspie-pending-workspace-since")
    (when (<= (+ it 2) (time.time))
      (return wnck-window._angelspie-pending-workspace)))
  (wnck-window.get_workspace))

(defn _window-xprop-value [prop_name]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  (ap-when (*current-xwindow*.get_full_property
             (*disp*.intern_atom prop_name)
             Xlib.X.AnyPropertyType)
    (. it.value [0])))

(defn _wnck-get-active-window []
  (for [window (_wnck-list-windows)]
    (when (window.is_active)
      (return window))))

(defn _wnck-list-screens []
  (setv screens [])
  (for [i (range 10)]
    (ap-when (Wnck.Screen.get i)
       (.append screens it)))
  screens)

(defn _wnck-list-windows []
  (setv windows [])
  (for [screen (_wnck-list-screens)]
    (screen.force-update)
    (setv windows (+ windows (screen.get_windows))))
  windows)

; ### DEVILSPIE FUNCTIONS/MACROS

(defn application_name []
  "Return the application name (as determined by libwnck) of the current window (String)."
  (.get_name (.get_application *current-window*)))

(defn above []
  "Set the current window to be above all normal windows, returns True."
  (*current-window*.make_above)
  True)

(defmacro begin [#*forms]
  "The devilspie equivalent of Hy's `do` : evaluates all the function calls within, returns the result of the last evaluation."
  `(do ~forms))

(defn below []
  "Set the current window to be below all normal windows, returns True."
  (*current-window*.make_below)
  True)

(defn center []
  "Center position of current window, returns boolean."
  (setv [x y w h] (*current-window*.get-geometry))
  (setv new-x (math.floor (- (/ (screen_width) 2)
                             (/ w 2))))
  (setv new-y (math.floor (- (/ (screen_height) 2)
                             (/ h 2))))
  (geometry (str+ "+" new-x "+" new-y)))

(defn close []
  "Close the current window, returns True."
  (*current-window*.close (time.time))
  True)

(defn contains [string substring]
  "True if string contains substring."
  (in substring string))

(defn debug []
  "Debugging function, outputs the current window's title, name, role and geometry (Returns TRUE)."
  (setv [x y w h] (_get-geometry))
  (print f"Window Title: '{(window_name)}'; Application Name: '{(application_name)}'; Class: '{(window_class)}'; Geometry: {w}x{h}+{x}+{y}")
  True)

(defn decorate []
  "Add the window manager decorations to the current window, returns boolean."
  (*current-xwindow*.change_property
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    (*disp*.intern_atom "_MOTIF_WM_HINTS")
    32
    [0x0 0x0 0x0 0x0 0x0]))

(defmacro dsif [cond-clause then-clause [else-clause None]]
  "Equivalent to Devilspie's if. Like Hy's builtin if, but the else clause is optional.
   Evaluates then-clause if cond-clause is True, else-clause otherwise if provided."
  `(if ~cond-clause
       ~then-clause
       ~(when else-clause else-clause)))

(defmacro dsprint [#*args]
  "Equivalent to Devilspie's print.
   Print args without trailing newline, returns boolean."
  (print #*args :sep ""
                :end ""
                :flush True))

(defn focus []
  "Focus the current window, returns True."
  (*current-window*.activate (time.time))
  True)

(defn fullscreen []
  "Make the current window fullscreen, returns True."
  (*current-window*.set_fullscreen True)
  True)

(defn geometry [geom-str]
  "Set position + size (as string) of current window, returns boolean.
   geom-str should be in X-GeometryString format:
    [=][<width>{xX}<height>][{+-}<xoffset>{+-}<yoffset>]
   as an extension to the X-GeometryString format, all values
   can be specified as percentages of screen/monitor size. For
   percentages of screen size, set setting \"ref-frame\" to RefFrame.SCREEN
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
  (unless geom-parts
    (print f"Invalid geometry: {geom-str}")
    (return False))
  (setv w (ap-when (.group geom-parts "w") (_hdimension_to-pixels it)))
  (setv h (ap-when (.group geom-parts "h") (_vdimension_to-pixels it)))
  (setv x (ap-when (.group geom-parts "x") (_hdimension_to-pixels it)))
  (setv y (ap-when (.group geom-parts "y") (_vdimension_to-pixels it)))
  (when (and (= (type x) int)
             (= (_getsetting "ref-frame") RefFrame.MONITOR))
    (setv monitor-geometry (. (_get-monitor) (get_geometry)))
    (setv x (+ (. monitor-geometry x) (or x 0)))
    (setv y (+ (. monitor-geometry y) (or y 0))))
  (_insist-on-geometry
    (when (= (type w) int)
      (*current-gdk-window*.resize w h))
    (when (= (type x) int)
      (*current-gdk-window*.move x y)))
  (return True))

(defn matches [string pattern]
  "True if the regexp pattern matches str"
  (bool (re.search pattern string)))

(defn opacity [level]
  "Change the opacity level (as integer in 0..100) of the current window, returns boolean."
	;v=0xffffffff/100*level;
	;XChangeProperty (gdk_x11_get_default_xdisplay (), wnck_window_get_xid(c->window),
	;	my_wnck_atom_get ("_NET_WM_WINDOW_OPACITY"),
	;	XA_CARDINAL, 32, PropModeReplace, (guchar *)&v, 1);
  ;(*current-gdk-window*.set-opacity (/ level 100))
  (_not-yet-implemented "opacity"))

(defn maximize []
  "Maximise the current window, returns True."
  (*current-window*.maximize)
  True)

(defn maximize_vertically []
  "Maximise vertically the current window, returns True."
  (*current-window*.maximize_vertically)
  True)

(defn maximize_horizontally []
  "Maximise horizontally the current window, returns True."
  (*current-window*.maximize_horizontally)
  True)

(defn minimize []
  "Minimise the current window, returns True."
  (*current-window*.minimize)
  True)

(defn pin []
  "Pin the current window to all workspaces, returns True."
  (*current-window*.pin)
  True)

(defn println [#*args]
  "Print args with trailing newline, returns True."
  (print #*args
         :sep "")
  True)

(defn set_viewport [viewport-nb]
  "Move the window to a specific viewport number, counting from 1, returns boolean."
  (_not-yet-implemented "set_viewport"))

(defn set_workspace [workspace-nb]
  "Move the window to a specific workspace number, counting from 1, returns boolean."
  (setv target-workspace (. *current-window*
                            (get_screen)
                            (get_workspaces)
                            [(- workspace-nb 1)]))
  (setv *current-window*._angelspie-pending-workspace target-workspace)
  (setv *current-window*._angelspie-pending-workspace-since (time.time))
  (*current-window*.move_to_workspace target-workspace))

(defn shade []
  "Shade ('roll up') the current window, returns True."
  (*current-window*.shade)
  True)

(defn skip_pager [[active True]]
  "Remove the current window from the window list, returns True.
   If passed active=False, puts the window back in the window list."
  (*current-window*.set_skip_pager active)
  True)

(defn skip_tasklist [[active True]]
  "Remove the current window from the pager, returns True.
   If passed active=False, puts the window back in the pager."
  (*current-window*.set_skip_tasklist active)
  True)

(defn spawn_async [#*cmd]
  "Execute a command in the background, returns boolean. Command is given as a single string, or as a series of strings (similar to execl)."
  (setv string-cmd (.join " " (map str cmd)))
  (_print-when-verbose "spawn_async" string-cmd)
  (subprocess.Popen ["bash" "-c" string-cmd]))

(defn spawn_sync [#*cmd]
  "Execute  a  command in the foreground (returns command output as string, or FALSE on error). Command is given as a single string, or as a series of strings (similar to execl)."
  (setv string-cmd (.join " " (map str cmd)))
  (_print-when-verbose "spawn" string-cmd)
  (.decode (. (subprocess.run ["bash" "-c" string-cmd] :stdout subprocess.PIPE)
              stdout)
           "utf-8"))

(defn stick []
  "Make the current window stick to all viewports, returns True."
  (_not-yet-implemented "stick"))

(defn str+ [#*args]
  "Transform parameters into strings and concat them with spaces in between."
  (. "" (join (list (map str args)))))

(defn undecorate []
  "Remove the window manager decorations from the current window, returns boolean."
  (*current-gdk-window*.set_decorations 0)
  (*current-gdk-window*.get_geometry)
  True)

(defn unmaximize []
  "Un-maximise the current window, returns True."
  (*current-window*.unmaximize)
  True)

(defn unminimize []
  "Un-minimise the current window, returns True."
  (*current-window*.unminimize (time.time))
  True)

(defn unpin []
  "Unpin the current window from all workspaces, returns True."
  (*current-window*.unpin)
  True)

(defn unshade []
  "Un-shade ('roll down') the current window, returns True."
  (*current-window*.unshade)
  True)

(defn unstick []
  "Unstick the window from viewports, returns True."
  (_not-yet-implemented "unstick")
  True)

(defn wintype [type]
  "Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop."
  (*current-window*.set_window_type (getattr Wnck.WindowType type)))

(defn window_class []
  "Return the class of the current window (String)."
  (*current-window*.get_class_group_name))

(defn window_name []
  "Return the title of the current window (String)."
  (str (*current-window*.get_name)))

(defn window_property [prop-name]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  (ap-when (_window-xprop-value prop-name)
     (*disp*.get_atom_name it)))

(defn window_role []
  "Return the role (as determined by the WM_WINDOW_ROLE hint) of the current window (String)."
  (*current-window*.get_role))

(defn window_workspace []
  "Returns the workspace the current window is on (Integer)."
  (+ (. *current-window*
        (get_workspace)
        (get_number))
     1))

(defn window_xid []
  "Return the X11 window id of the current window (Integer)."
  (*current-window*.get_xid))

; ### ADDITIONS TO DEVILSPIE

(setv _*settings* {})
(defmacro setting [varname val-form]
  "Set Angelspie setting <varname> to the result of evaluating val-form
   in each window/monitor/etc. context where the setting is needed."
  `(setv (. _*settings* [~(str varname)] ["fn"])
         (fn [] ~val-form)))

(defn _getsetting [varname]
  (setv val ((. _*settings* [varname] ["fn"])))
  (unless (isinstance val
                      (. _*settings* [varname] ["type"]))
    (raise (TypeError f"Invalid type for setting '{varname}': {(type it)}")))
  val)

(defn _defsetting [varname default valtype]
  (setv (. _*settings* [varname])
        {
          "fn" (fn [] default)
          "type" valtype
        }))

(defclass RefFrame [Enum]
  "Used for setting ref-frame.
   RefFrame.MONITOR is the default and means that percent values and tile patterns will be relative to the window's current monitor, RefFrame.SCREEN means that percent values and tile patterns will be relative to the whole virtual screen, which might span multiple monitors depending on your setup."
  (setv MONITOR 0)
  (setv SCREEN 1))

(_defsetting "ref-frame" RefFrame.MONITOR RefFrame)
(_defsetting "tile-margin-top"    0 (| int str))
(_defsetting "tile-margin-bottom" 0 (| int str))
(_defsetting "tile-margin-left"   0 (| int str))
(_defsetting "tile-margin-right"  0 (| int str))
(_defsetting "tile-col-gap"       0 (| int str))
(_defsetting "tile-row-gap"       0 (| int str))

(defn monitor []
  "Returns the connector name of the current window's monitor (i.e. the one that has most of the window in it)."
  (setv gdk-monitor-geom (. (_get-monitor) (get_geometry)))
  (for [m (. *disp*
             (screen)
             root
             (xrandr_get_monitors)
             monitors)]
     (when (and (= m.x gdk-monitor-geom.x)
                (= m.y gdk-monitor-geom.y))
       (return (. *disp* (get_atom_name m.name))))))
  
(defn monitor-connected [connector-name]
  "Returns True if monitor with connector connector-name is connected, false otherwise"
  (bool (_get-xmonitor-by-connector-name connector-name)))

(defn monitor-height []
  "Returns the height in pixels of the current window's monitor (i.e. the one that has most of the window in it)."
  (. (_get-monitor)
     (get_geometry)
     height))

(defn monitor-is-primary []
  "Returns True if the current window's monitor (i.e. the one that has most of the window in it) is primary, False otherwise."
  (. (_get-monitor)
     (is_primary)))

(defn monitor-width []
  "Returns the width in pixels of the current window's monitor (i.e. the one that has most of the window in it)."
  (. (_get-monitor)
     (get_geometry)
     width))

(defmacro on-class-change [#*args]
  "Attaches <callback> to class changes on the current window."
  `(_attach_to_window_event "class-changed" (fn [] ~args)))

(defmacro on-icon-change [#*args]
  "Attaches <callback> to icon changes on the current window."
  `(_attach_to_window_event "icon-changed" (fn [] ~args)))

(defmacro on-name-change [#*args]
  "Attaches <callback> to name changes on the current window."
  `(_attach_to_window_event "name-changed" (fn [] ~args)))

(defn set-monitor [monitor-ref-or-direction [preserve-tiling False]]
  "Move window to monitor identified by `monitor-ref-or-direction`.
  `monitor-ref-or-direction` can be one of \"left\", \"right\",
  \"up\" or \"down\" relative to the current window's monitor
  (i.e. the one that has most of the window in it) or it can be
  the monitor's connector name as defined by Xrandr (ex: \"DP1\",
  \"HDMI1\", etc.
  If preserve-tiling is true, the tiling pattern last set
  for this window will be reapplied after moving it to the
  new monitor.
  Returns True if move was successful, False otherwise."
  (setv was-maximized (*current-window*.is-maximized))
  (setv was-vmaximized (*current-window*.is-maximized-vertically))
  (setv was-hmaximized (*current-window*.is-maximized-horizontally))
  (unmaximize)
  (setv target-monitor (_get-monitor monitor-ref-or-direction))
  (unless target-monitor
    (print f"No monitor found for monitor-ref-or-direction '{monitor-ref-or-direction}'")
    (return False))
  (setv current-monitor-geom (. (_get-monitor) (get_geometry)))
  (setv target-monitor-geom  (. target-monitor (get_geometry)))
  (setv [current-x current-y _ _] (*current-window*.get-geometry))
  (setv new-x (+ (- current-x (. current-monitor-geom x)) (. target-monitor-geom x)))
  (setv new-y (+ (- current-y (. current-monitor-geom y)) (. target-monitor-geom y)))
  (_insist-on-geometry
    (*current-gdk-window*.move new-x new-y))
  (when preserve-tiling
    (tile-at "last"))
  (if was-maximized
      (maximize)
      (do (when was-vmaximized (maximize-vertically))
          (when was-hmaximized (maximize-horizontally))))
  (return True))

(defn tile [[v-pattern "*"]
            [h-pattern "*"]]
  "Tile the current window according to v-pattern and h-pattern.
   Patterns are composed of the plus sign (+) which represents the window
   and underscores (_) which represent empty space.
   For example, a vertical pattern of _+_ means the window will be in the middle row of
   a screen divided into three sections. A horizontal pattern of + means that
   the window will take the whole screen horizontally.
   Frame defines what we tile relative to (see ref-frame in settings)."
  (unmaximize)
  (unless (_is-valid-tile-pattern v-pattern)
    (print f"Invalid tile pattern: {v-pattern}")
    (return False))
  (unless (_is-valid-tile-pattern h-pattern)
    (print f"Invalid tile pattern: {h-pattern}")
    (return False))
  (setv rows (len v-pattern))
  (setv cols (len h-pattern))
  (setv col-gap-px       (_hdimension-to-pixels (_getsetting "tile-col-gap")))
  (setv row-gap-px       (_vdimension-to-pixels (_getsetting "tile-row-gap")))
  (setv margin-left-px   (_hdimension-to-pixels (_getsetting "tile-margin-left")))
  (setv margin-right-px  (_hdimension-to-pixels (_getsetting "tile-margin-right")))
  (setv margin-top-px    (_vdimension-to-pixels (_getsetting "tile-margin-top")))
  (setv margin-bottom-px (_vdimension-to-pixels (_getsetting "tile-margin-bottom")))
  (setv frame-width-px   (_hdimension-to-pixels "100%"))
  (setv frame-height-px  (_vdimension-to-pixels "100%"))
  (setv col-width-px (/ (- frame-width-px
                           margin-left-px
                           margin-right-px
                           (* (- cols 1) col-gap-px))
                         cols))
  (setv row-height-px (/ (- frame-height-px
                            margin-top-px
                            margin-bottom-px
                            (* (- rows 1) row-gap-px))
                         rows))
  (setv x (. h-pattern (index "*")))
  (setv x-px (math.floor (+ margin-left-px
                            (* col-width-px x)
                            (* col-gap-px x))))
  (setv y (. v-pattern (index "*")))
  (setv y-px (math.floor (+ margin-top-px
                            (* row-height-px y)
                            (* row-gap-px y))))
  (setv w (. h-pattern (count "*")))
  (setv w-px (math.floor (* col-width-px w)))
  (setv h (. v-pattern (count "*")))
  (setv h-px (math.floor (* row-height-px h)))
  (ap-with (shelve.open +last-pattern-shelve+)
    (assoc it (str (window_xid)) [v-pattern h-pattern]))
  (_print-when-verbose f"TILE {w-px}x{h-px}+{x-px}+{y-px}")
  (geometry (str+ w-px "x" h-px "+" x-px "+" y-px)))

(defn _last-tiling-pattern []
  (ap-with (shelve.open (os.path.join +last-pattern-shelve+))
    (when (in (str (window_xid)) it)
      (. it [(str (window_xid))]))))

(defn tile-at [position]
  "Tile the current window. `position` can be one of :
     - \"last\"          resume the last tiling pattern for this particular window
     - \"left\"          which is equivalent to `(tile \"*\"    \"*_\" )`
     - \"right\"         which is equivalent to `(tile \"*\"    \"_*\" )`
     - \"top\"           which is equivalent to `(tile \"_*\"   \"*\"  )`
     - \"top-left\"      which is equivalent to `(tile \"_*\"   \"*_\" )`
     - \"top-right\"     which is equivalent to `(tile \"_*\"   \"_*\" )`
     - \"center\"        which is equivalent to `(tile \"_*_*\" \"__*\")`
     - \"center-left\"   which is equivalent to `(tile \"_*_*\" \"*_\" )`
     - \"center-right\"  which is equivalent to `(tile \"_*_*\" \"_*\" )`
     - \"bottom\"        which is equivalent to `(tile \"_*\"   \"*\"  )`
     - \"bottom-left\"   which is equivalent to `(tile \"_*\"   \"*_\" )`
     - \"bottom-right\"  which is equivalent to `(tile \"_*\"   \"_*\" )`
     - \"full\"          which is equivalent to `(tile \"*\"    \"*\"  )`
   See the documentation for `tile` for more information."
  (case position
    "last"         (ap-if (_last-tiling-pattern)
                      (return (tile #* it))
                      (do (print "No last tiling pattern for this window")
                          (return False)))
    "left"         (return (tile "*"    "*_" ))
    "right"        (return (tile "*"    "_*" ))
    "up"           (return (tile "*_"   "*"  ))
    "top"          (return (tile "*_"   "*"  ))
    "top-left"     (return (tile "*_"   "*_" ))
    "top-right"    (return (tile "*_"   "_*" ))
    "center"       (return (tile "__*"  "__*"))
    "center-left"  (return (tile "_*_*" "*_" ))
    "center-right" (return (tile "_*_*" "_*" ))
    "bottom"       (return (tile "_*"   "*"  ))
    "down"         (return (tile "_*"   "*"  ))
    "bottom-left"  (return (tile "_*"   "*_" ))
    "bottom-right" (return (tile "_*"   "_*" ))
    "full"         (return (tile "*"    "*"  ))
    else           (do (print f"Invalid position for tile : '{position}'")
                       (return False))))

(defn tile-move [direction]
  "Move the current window in <direction> within
   its current tiling pattern."
  (ap-if (_last-tiling-pattern)
    (setv [v-pattern h-pattern] it)
    (return (tile-at direction)))
  (case direction
    "left"   (setv [new-v-pattern new-h-pattern]
                   [v-pattern (_tile-inc-pattern h-pattern -1)])
    "right"  (setv [new-v-pattern new-h-pattern]
                   [v-pattern (_tile-inc-pattern h-pattern 1)])
    "up"     (setv [new-v-pattern new-h-pattern]
                   [(_tile-inc-pattern v-pattern -1) h-pattern])
    "down"   (setv [new-v-pattern new-h-pattern]
                   [(_tile-inc-pattern v-pattern 1) h-pattern])
    else     (do (print f"Invalid direction for tile-move : '{direction}'")
                 (return False)))
  (when (and (= (_getsetting "ref-frame")
                RefFrame.MONITOR)
             (= new-v-pattern v-pattern)
             (= new-h-pattern h-pattern)
             (_get-monitor direction))
    (when (in direction ["left" "right"])
      (setv h-pattern (. h-pattern (reverse))))
    (when (in direction ["up" "down"])
      (setv h-pattern (. h-pattern (reverse))))
    (set-monitor direction))
  (tile new-v-pattern new-h-pattern))

(defn screen-height []
  "Returns the height in pixels of the current window's screen."
  (. *current-window*
     (get_screen)
     (get_height)))

(defn screen-width []
  "Returns the width in pixels of the current window's screen."
  (. *current-window*
     (get_screen)
     (get_width)))

(defn unfullscreen []
  "Make the current window not fullscreen, returns True."
  (*current-window*.set_fullscreen False)
  True)
  
(defn window-index []
  "Returns the index of the window in the taskbar."
  (*current-window*.get_sort_order))
  
(defn window-index-in-class []
  "Returns the index of the window in the taskbar, counting only the windows of the same class."
  (setv index 0)
  (for [w (sorted (_wnck-list-windows) :key (fn [ww] (str (ww.get_sort_order))))]
     (when (= (w.get_class_group_name)
              (window_class))
       (when (= w *current-window*)
         (break))
       (setv index (+ index 1))))
  (_print-when-verbose "INDEX IN CLASS" index)
  index)
  
(defn window-index-in-workspace []
  "Returns the index of the window in the taskbar, counting only the windows of the same workspace."
  (setv index 0)
  (setv workspace (_window-prospective-workspace *current-window*))
  (for [win (sorted (_wnck-list-windows) :key (fn [ww] (str (ww.get_sort_order))))]
    (ap-when (_window-prospective-workspace win)
      (when (= it workspace)
        (when (= win *current-window*)
          (break))
        (setv index (+ index 1)))))
  (_print-when-verbose "INDEX IN WORKSPACE" index)
  index)

(defn window-type [type]
  "Set the window type of the current window, returns boolean. Accepted values are: normal, dialog, menu, toolbar, splashscreen, utility, dock, desktop."
  (wintype type))

;;  MAIN

(setv *scripts* {})
(defn _process-window [window [is-second-run False]]
  (_with-window window
    (for [script-name (*scripts*.keys)]
      (_print-when-verbose "== Running" script-name)
      (hy.eval (hy.read-many (get *scripts* script-name))))
    (for [eval-str *command-line-args*.eval]
      (hy.eval (hy.read-many eval-str)))))

(defn _on-monitors-changed [screen]
  (_print-when-verbose "NEW SCREEN CONFIG, RESTARTING ++++++")
  (list (map _process-window (_wnck-list-windows))))

(defn _on-new-window [screen window]
  (_print-when-verbose "NEW WINDOW ++++++")
  (_process-window window))

(defn _attach-handler-to-all-screens []
  (for [wnck-screen (_wnck-list-screens)]
    (wnck-screen.connect "window-opened" _on-new-window))
  (for [gdk-screen-nb (range (*gdk-disp*.get_n_screens))]
    (. *gdk-disp*
       (get_screen gdk-screen-nb)
       (connect "monitors-changed" _on-monitors-changed))))

(defn _load-scripts []
  (for [as-file (if (or *command-line-args*.load *command-line-args*.eval)
                      *command-line-args*.load
                      (sorted (glob.glob (os.path.join +config-dir+ "*.as"))))]
      (with [as-handle (open as-file)]
        (setv (get *scripts* as-file) (as-handle.read)))))

(defn _main-loop []
  (_try-to-build-config-from-devilspie-if-we-have-none)
  (when (and (not (glob.glob (os.path.join +config-dir+ "*.as")))
             (not *command-line-args*.load))
    (print "No configuration file found and none specified in command-line")
    (sys.exit 1))
  (. (pathlib.Path +last-pattern-shelve+)
     (unlink :missing_ok True))
  (_attach-handler-to-all-screens)
  (GLib.unix_signal_add
    GLib.PRIORITY_DEFAULT
    signal.SIGINT
    (fn []
      (Wnck.shutdown)
      (Gtk.main_quit)))
  (Gtk.main))

(setv *command-line-args* (_parse-command-line))

(_print-when-verbose *command-line-args*)

(when *command-line-args*.docs
  (_docs)
  (sys.exit 0))

(_load-scripts)
(if *command-line-args*.eval
  (_process-window (_wnck-get-active-window))
  (_main-loop))
