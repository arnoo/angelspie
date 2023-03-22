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
(import functools)
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
(import sys)
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
       (try
            ~@forms
            (except [e [Xlib.error.BadDrawable Xlib.error.BadWindow]]
               (_print-when-verbose "Window closed during script execution")
               (return False)))
       (ap-when (*gdk-disp*.error_trap_pop)
         (print "GDK ERROR" it)
         (return False))))

(defn _attach-to-window-event [event-name callback]
  (setv attr-name (+ "_angelspie-" event-name "callbacks"))
  (unless (hasattr *current-window* attr-name)
    (setattr *current-window* attr-name (set))
    (*current-window*.connect
      event-name
      (fn [win]
         (_with-window win
          (lfor c (getattr *current-window* attr-name) (c.call))))))
  (. (getattr *current-window* attr-name)
     (add callback)))
  
(defclass _callback_with_code_hash []
  (defn __init__ [self lambda]
    (setv self.lambda lambda))

  (defn __hash__ [self]
    (hash self.lambda.__code__.co_code))

  (defn call [self #*args]
    (self.lambda #*args))

  (defn __eq__ [self other]
    (= (self.__hash__) (other.__hash__))))
  
(defn _docs []
  "Returns the API docs as Markdown"
  (with [source-handle (open (os.path.abspath __file__))]
    (for [line (source-handle.readlines)]
      (when (or (line.startswith "(defn")
                (line.startswith "(defmacro"))
        (if (line.startswith "(defn [")
          (setv [_ _ func-name func-args] (line.split " " 3))
          (setv [_ func-name func-args] (line.split " " 2)))
        (unless (func-name.startswith "_")
          (setv func-args
            (if (= func-args "[]")
                ""
                (+ " " (cut func-args 1 -2))))
          (when (= func-args " ")
            (setv func-args ""))
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

(defn [functools.cache] _favicon-for-url [url [use-full-url False]]
  (import favicon)
  (setv headers {"User-Agent" "Angelspie"})
  (for [icon (favicon.get (if use-full-url
                              url
                              (. "/" (join (cut (url.split "/" 4) 0 3))))
                          :headers headers)]
    (when (and (= (. icon format) "png")
               (>= (. icon width) 32))
      (return (. icon url)))
    (when (= (. icon format) "ico")
      (return (. icon url)))))

(defn _geoms-intersect [geom1 geom2]
  (setv [x1 y1 w1 h1] geom1)
  (setv [x2 y2 w2 h2] geom2)
  (not (or (> x1 (+ x2 w2))
           (< (+ x1 w1) x2)
           (> y1 (+ y2 h2))
           (< (+ y1 h1) y2))))

(defn _get-accessible-child-by-attr-value [accessible attr value]
  (import pyatspi)
  (pyatspi.findDescendant accessible
                          (fn [x] (= (. x (get_attributes) [attr])
                                     value))
                          :breadth_first True))

(defn _get-geometry [win]
  "Return the window's geometry in the
   context of the ref_frame set in settings."
  (setv [x y w h] (win.get-geometry))
  (when (= (_getsetting "ref-frame")
           RefFrame.MONITOR)
    (setv monitor-geom
          (. (_get-monitor)
            (get_geometry)))
    (setv x (- x (. monitor-geom x)))
    (setv y (- y (. monitor-geom y))))
  [x y w h])

(defn _get-edid [monitor]
  (str (. (bytearray
            (. (*disp*.xrandr_get_output_property (get monitor.crtcs 0)
                                                  (*disp*.intern_atom "EDID")
                                                  Xlib.X.AnyPropertyType
                                                  0
                                                  100)
                _data
                ["value"]))
          (hex)) "utf-8"))

(defn _get-xmonitor-by-connector-name [connector-name [EDID None]]
  (for [m (. *disp*
             (screen)
             root
             (xrandr_get_monitors)
             monitors)]
     (when EDID
       (unless (= (_get-edid m) EDID)
         (continue)))
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
      "primary" (for [monitor-index (range (*gdk-disp*.get_n_monitors))]
                   (when (. (*gdk-disp*.get_monitor monitor-index)
                            (is_primary))
                     (return (*gdk-disp*.get_monitor monitor-index))))
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

(defn _get-prospective-prop [obj prop [default None] [prospective True] [timeout-secs 2]]
  (when (and prospective
             (hasattr obj (+ "_angelspie_pending_" prop "_since")))
      (when (<= (time.time)
                (+ (getattr obj (+ "_angelspie_pending_" prop "_since"))
                   timeout-secs))
        (return (getattr obj (+ "_angelspie_pending_" prop)))))
  default)

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
       ~@forms
       ;Calling get_geometry after resize/move seems necessary for some reason
       (*current-gdk-window*.get_geometry))))

(defn _is-valid-tile-pattern [pattern]
  (bool (re.match "^_*[*]+_*$" pattern)))

(defn _parse-command-line [args]
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
                 "--load"
                 :default []
                 :help "as script to run for each window (by default ~/.config/angelspie/*.as)"
                 :metavar "LOAD_FILE"
                 :nargs "*")
  (parser.add-argument 
                 "-v"
                  "--verbose"
                 :action "store_const"
                 :const True
                 :help "Verbose output")
  (parser.add-argument
                 "--wid"
                 :help "Execute scripts once, for window with XID <wid>."
                 :nargs "?")
  (parser.parse-args))

(defn _not-yet-implemented [fn-name]
  (print f"WARNING: Call to function '{fn-name}' which is not yet implemented."))

(defn _print-when-verbose [#*args]
  (when *command-line-args*.verbose
     (print #*args)))

(defn _set-prospective-prop [obj prop value]
  (setattr obj (+ "_angelspie_pending_" prop) value)
  (setattr obj (+ "_angelspie_pending_" prop "_since") (time.time)))

(defn _tile-inc-pattern [pattern increment]
  (if (> increment 0)
    (if (pattern.endswith "*")
        pattern
        (+ "_" (cut pattern 0 -1)))
    (if (pattern.startswith "*")
        pattern
        (+ (cut pattern 1 None) "_"))))

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
  (ap-when (hasattr wnck-window "_angelspie_pending_workspace_since")
    (when (<= (+ it 2) (time.time))
      (return wnck-window._angelspie-pending-workspace)))
  (wnck-window.get_workspace))

(defn _window-xprop-value [prop_name]
  "Returns the given property of the window, e.g. pass '_NET_WM_STATE' (String)."
  (ap-when (*current-xwindow*.get_full_property
             (*disp*.intern_atom prop_name)
             Xlib.X.AnyPropertyType)
    (. it.value [0])))

(defn _wnck-get-active-window [[force-update False]]
  (for [window (_wnck-list-windows :force-update force-update)]
    (when (window.is_active)
      (return window))))

(defn _wnck-get-window-by-xid [xid [force-update False]]
  (setv xid (if (xid.startswith "0x")
                (int.from_bytes (bytes.fromhex (cut xid 2 None)) "big")
                (int xid)))
  (for [window (_wnck-list-windows :force-update force-update)]
    (when (= (window.get_xid) xid)
      (return window)))
  (print f"No window found with XID {xid}")
  (sys.exit 1))

(defn _wnck-list-screens []
  (setv screens [])
  (for [i (range 10)]
    (ap-when (Wnck.Screen.get i)
       (.append screens it)))
  screens)

(defn _wnck-list-windows [[force-update False]]
  (setv windows [])
  (for [screen (_wnck-list-screens)]
    (when force-update
      (screen.force-update))
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
  `(do ~@forms))

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
  (setv [x y w h] (_get-geometry *current-window*))
  (print f"Window Title: '{(window_name)}'; Application Name: '{(application_name)}'; Class: '{(window_class)}'; Geometry: {w}x{h}+{x}+{y}")
  True)

(defn decorate []
  "Add the window manager decorations to the current window, returns boolean."
  (*current-gdk-window*.set_decorations 2)
  (*current-gdk-window*.get_geometry)
  True)

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

(defn _parse-geom-str [geom-str]
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
    (throw (ValueError)))
  (setv w (ap-when (.group geom-parts "w") (_hdimension_to-pixels it)))
  (setv h (ap-when (.group geom-parts "h") (_vdimension_to-pixels it)))
  (setv x (ap-when (.group geom-parts "x") (_hdimension_to-pixels it)))
  (setv y (ap-when (.group geom-parts "y") (_vdimension_to-pixels it)))
  (when (and (= (type x) int)
             (= (_getsetting "ref-frame") RefFrame.MONITOR))
    (setv monitor-geometry (. (_get-monitor) (get_geometry)))
    (setv x (+ (. monitor-geometry x) (or x 0)))
    (setv y (+ (. monitor-geometry y) (or y 0))))
  [x y w h])

(defn geometry [geom-str]
  "Set position + size (as string) of current window, returns boolean.
   geom-str should be in X-GeometryString format:
    `[=][<width>{xX}<height>][{+-}<xoffset>{+-}<yoffset>]`
   as an extension to the X-GeometryString format, all values
   can be specified as percentages of screen/monitor size. For
   percentages of screen size, set setting \"ref-frame\" to RefFrame.SCREEN
   Examples:
       `(geometry \"400×300+0-22\")`
       `(geometry \"640×480\")`
       `(geometry \"100%×50%+0+0\")`
       `(geometry \"+10%+10%\")`"
  (try
    (setv [x y w h] (_parse-geom-str geom-str))
    (except [ValueError]
      (return False)))
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
  ; opacity_atom = *disp*.get_atom('_NET_WM_WINDOW_OPACITY')
  ; level = 50
  ; v = int(0xffffffff / 100 * level)
  ; data = struct.pack('I', v)
  ; *disp*.change_property(wnck_window_xid, opacity_atom, X.Cardinal, 32, X.PropModeReplace, data)
  ;(*current-xwindow*.change_property
  ;  (*disp*.intern_atom "_MOTIF_WM_HINTS")
  ;  (*disp*.intern_atom "_MOTIF_WM_HINTS")
  ;  32
  ;  data)
  (_not-yet-implemented "opacity"))

;TODO ?
;(defn disable_mouseover []
;  (*current-xwindow*.grab_pointer
;     True
;     Xlib.X.EnterWindowMask
;     Xlib.X.GrabModeSync ; pointer_mode
;     Xlib.X.GrabModeSync ; keyboard_mode
;     0 ; confine_to
;     0 ; cursor
;     (time.time) ;time
;     ))
;  (setv event_mask X.PointerMotionMask)
;  (*current-xwindow*.change_attributes
;    :event_mask event_mask
;    :do_not_propagate_mask event_mask
;    :cursor X.NONE
;    :override_redirect True
;    :enter_window: 0
;    :leave_window: 0))

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
  (*current-window*.move_to_workspace target-workspace)
  (_set-prospective-prop *current-window*
                         "workspace"
                         workspace-nb))

(defn shade []
  "Shade ('roll up') the current window, returns True."
  (*current-window*.shade)
  True)

(defn skip_pager [[active True]]
  "Remove the current window from the window list, returns True.
   If passed `active=False`, puts the window back in the window list."
  (*current-window*.set_skip_pager active)
  True)

(defn skip_tasklist [[active True]]
  "Remove the current window from the pager, returns True.
   If passed `active=False`, puts the window back in the pager."
  (*current-window*.set_skip_tasklist active)
  True)

(defn spawn_async [#*cmd]
  "Execute a command in the background, returns boolean. Command is given as a single string, or as a series of strings (similar to execl)."
  (import subprocess)
  (setv string-cmd (.join " " (map str cmd)))
  (_print-when-verbose "spawn_async" string-cmd)
  (subprocess.Popen ["bash" "-c" string-cmd]))

(defn spawn_sync [#*cmd]
  "Execute  a  command in the foreground (returns command output as string, or `False` on error). Command is given as a single string, or as a series of strings (similar to execl)."
  (import subprocess)
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

(defn window_class [[prospective True]]
  "Return the class of the current window (String).
   If `prospective=True`, will return the class the window
   is expected to have soon due to a possible call to set-window-class."
  (_get-prospective-prop *current-window*
                         "class"
                         (*current-window*.get_class_group_name)
                         :prospective prospective))

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

(defn window_workspace [[window None] [prospective True]]
  "Returns the workspace the current window is on (Integer).
   If `prospective=True` will return the workspace the window
   is on or is expected to be on soon due to a pending
   set-window-workspace call."
  (unless window
    (setv window *current-window*))
  (_get-prospective-prop window
                         "workspace"
                         (ap-when (. window (get_workspace))
                          (+ (. it (get_number))
                             1))
                         :prospective prospective))

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

(defn browser-favicon [[use-full-url False]]
  (ap-when (browser-url)
    (_favicon-for-url it :use-full-url use-full-url)))

(defn browser-url []
  (import pyatspi)
  (setv wname (window-name))
  (case (window_class)
    "Chromium" (do (setv accessible-name "Chromium")
                   (setv urlbar-attr "class")
                   (setv urlbar-attr-val "OmniboxViewViews"))
    "firefox"  (do (setv accessible-name "Firefox")
                   (setv urlbar-attr "id")
                   (setv urlbar-attr-val "urlbar-input"))
    else       (do (print "(browser-url) called with non browser window or unsupported browser")
	           (return None)))
  (setv root (. pyatspi Registry (getDesktop 0)))
  (setv browser-accessibles [])
  (for [i (range (root.get_child_count))]
    (setv app-accessible (. root (getChildAtIndex i)))
    (when (= app-accessible.name accessible-name)
       (browser-accessibles.append app_accessible)))
  (unless (> (len browser-accessibles) 0)
    (print "ERROR: could not find browser accessible. Is the GNOME_ACCESSIBILITY env variable set to 1 ?")
    (return None))
  (for [browser-accessible browser-accessibles]
    (for [i (range (browser-accessible.get_child_count))]
      (setv browser-window (. browser-accessible (getChildAtIndex i)))
      (when (browser-window.name.startswith wname)
        (print browser-window.name ".startswith" wname)
        (setv url-bar (_get-accessible-child-by-attr-value browser-window
                                                          urlbar-attr
                                                          urlbar-attr-val))
        (when (= url-bar None)
          (print "URL BAR NOT FOUND")
          (import pprint)
          (pyatspi.findDescendant browser-window
                          (fn [x] (print x) (pprint.pprint (.x (get_attributes)))
                                  (= (. x (get_attributes) [urlbar-attr])
                                     urlbar-attr-val))
                          :breadth_first True)
          (print "========="))
        (setv url (. url-bar
                    (queryText)
                    (getText 0 -1)))
        (when (= (window_class) "Chromium")
          (when (= url "Address and search bar")
            (return None))
          (setv location-icon-text
                (. (_get-accessible-child-by-attr-value browser-window
                                                        "class"
                                                        "LocationIconView")
                   (get_description)))
          (setv url (+ (if (= location-icon-text "Not secure") "http" "https") "://" url)))
        (return url))))
  (return None))

(defn empty [geom-str [workspace-nb None]]
  "Returns True if rectangle corresponding to geom-str is empty,
   i.e. no windows intersect the rectangle, on the workspace
   of the current window or on workspace number <workspace-nb>
   if specified. Returns False if there is an intersecting window.
   The current window is ignored, as are minimized windows."
  (try
    (setv target-geom (_parse-geom-str geom-str))
    (except [ValueError]
      (return False)))
  (unless workspace-nb
    (setv workspace-nb (window_workspace)))
  (for [window (_wnck-list-windows)]
    (setv wworkspace (window-workspace window))
    (unless (and wworkspace 
                (= wworkspace workspace-nb))
      (continue))
    (when (or (= window *current-window*)
              (window.is-minimized))
      (continue))
    (setv window-geom (_get-geometry window))
    (when (_geoms-intersect window-geom target-geom)
      (return False)))
  (return True))

(defn monitor []
  "Returns the connector name of the current window's monitor
   i.e. the one that has most of the window in it."
  (setv gdk-monitor-geom (. (_get-monitor) (get_geometry)))
  (for [m (. *disp*
             (screen)
             root
             (xrandr_get_monitors)
             monitors)]
     (when (and (= m.x gdk-monitor-geom.x)
                (= m.y gdk-monitor-geom.y))
       (return (. *disp* (get_atom_name m.name))))))

(defn monitor-edid [[connector-name None]]
  "Returns the EDID of the current monitor, or, if
   `connector-name` is supplied, of the corresponding
   monitor.
   Returns None if no matching monitor is found for
   connector-name."
  (ap-when (_get-xmonitor-by-connector-name (or connector-name (monitor)))
    (_get-edid it)))
  
(defn monitor-connected [connector-name [EDID None]]
  "Returns True if monitor with connector connector-name is connected, False otherwise.
   If EDID is supplied, returns True only if the monitor's EDID matches.
   To get the connector name for a monitor type `xrand` in your terminal.
   To get the EDID for a monitor use Angelspie function
   `(monitor-edid connector-name)`."
  (bool (_get-xmonitor-by-connector-name connector-name)))

(defn monitor-height []
  "Returns the height in pixels of the current window's
   monitor, i.e. the one that has most of the window in it."
  (. (_get-monitor)
     (get_geometry)
     height))

(defn monitor-is-primary []
  "Returns `True` if the current window's monitor,
   i.e. the one that has most of the window in it,
   is primary, `False` otherwise."
  (. (_get-monitor)
     (is_primary)))

(defn monitor-width []
  "Returns the width in pixels of the current window's
   monitor, i.e. the one that has most of the window in it."
  (. (_get-monitor)
     (get_geometry)
     width))

(defmacro on-class-change [#*forms]
  "Runs <forms> on class changes of the current window."
  `(_attach-to-window-event "class-changed" (_callback_with_code_hash (fn [] ~@forms))))

(defmacro on-icon-change [#*forms]
  "Runs <forms> on icon changes of the current window."
  `(_attach-to-window-event "icon-changed" (_callback_with_code_hash (fn [] ~@forms))))

(defmacro on-name-change [#*forms]
  "Runs <forms> on name changes of the current window."
  `(_attach-to-window-event "name-changed" (_callback_with_code_hash (fn [] ~@forms))))

(setv _*monitors-callbacks* (set))
(defmacro on-monitors-change [#*forms]
  "Runs <forms> on changes in monitor setup."
  `(_*monitors-callbacks*.add (_callback_with_code_hash (fn [] ~@forms))))

(defn set-monitor [monitor-ref-or-direction [preserve-tiling False]]
  "Move window to monitor identified by `monitor-ref-or-direction`.
  `monitor-ref-or-direction` can be one of \"left\", \"right\",
  \"up\" or \"down\" relative to the current window's monitor
  (i.e. the one that has most of the window in it), \"primary\" for
  the primary monitor or it can be the monitor's connector name as
  defined by Xrandr (ex: \"DP1\", \"HDMI1\", etc.
  If preserve-tiling is true, the tiling pattern last set
  for this window will be reapplied after moving it to the
  new monitor.
  Returns `True` if move was successful, `False` otherwise."
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
  (setv w-px (math.floor (+ (* col-width-px w)
                            (* col-gap-px (- w 1)))))
  (setv h (. v-pattern (count "*")))
  (setv h-px (math.floor (+ (* row-height-px h)
                            (* col-gap-px (- h 1)))))
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
     - \"center\"        which is equivalent to `(tile \"_**_\" \"_**_\")`
     - \"center-left\"   which is equivalent to `(tile \"_**_\" \"*_\" )`
     - \"center-right\"  which is equivalent to `(tile \"_**_\" \"_*\" )`
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
    "center"       (return (tile "_**_"  "_**_"))
    "center-left"  (return (tile "_**_" "*_" ))
    "center-right" (return (tile "_**_" "_*" ))
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

(defn set-window-class [class]
  (_set-prospective-prop *current-window*
                         "class"
                         class)
  (*current-xwindow*.set_wm_class class class))

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
  index)
  
(defn window-index-in-workspace []
  "Returns the index of the window in the taskbar, counting only the windows of the same workspace."
  (setv index 0)
  (setv workspace (window_workspace))
  (for [win (sorted (_wnck-list-windows) :key (fn [ww] (str (ww.get_sort_order))))]
    (ap-when (window-workspace win)
      (when (= it workspace)
        (when (= win *current-window*)
          (break))
        (setv index (+ index 1)))))
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
      (hy.eval (hy.read-many (get *scripts* script-name)) :filename script-name :locals (globals)))
    (for [eval-str *command-line-args*.eval]
      (hy.eval (hy.read-many eval-str) :locals (globals)))))

(defn _on-monitors-changed [screen]
  (_print-when-verbose "NEW SCREEN CONFIG, RESTARTING ++++++")
  (list (map _process-window (_wnck-list-windows)))
  (for [callback _*monitors-callbacks*]
       (callback.call)))

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
    GLib.PRIORITY_HIGH
    signal.SIGINT
    (fn []
      (Gtk.main_quit)
      (Wnck.shutdown)))
  (Gtk.main))

(defn _main [[args None]]
  (global *command-line-args*)
  (setv *command-line-args*
        (_parse-command-line (or args
                                 (cut sys.argv 1 -1))))
  (_print-when-verbose *command-line-args*)
  
  (when *command-line-args*.docs
    (_docs)
    (sys.exit 0))
  
  (_load-scripts)
  (if (or *command-line-args*.eval
          *command-line-args*.wid)
    (_process-window (if *command-line-args*.wid
                         (_wnck-get-window-by-xid *command-line-args*.wid :force-update True)
                         (_wnck-get-active-window :force-update True)))
    (_main-loop)))

(when (= __name__ "__main__")
  (_main))
