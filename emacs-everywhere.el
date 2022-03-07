;;; emacs-everywhere.el --- System-wide popup windows for quick edits -*- lexical-binding: t; -*-

;; Copyright (C) 2021 TEC

;; Author: TEC <https://github.com/tecosaur>
;; Maintainer: TEC <tec@tecosaur.com>
;; Created: February 06, 2021
;; Modified: February 06, 2021
;; Version: 0.1.0
;; Keywords: conenience, frames
;; Homepage: https://github.com/tecosaur/emacs-everywhere
;; Package-Requires: ((emacs "26.3"))

;;; License:

;; This file is part of org-pandoc-import, which is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;  System-wide popup Emacs windows for quick edits

;;; Code:

(require 'cl-lib)
(require 'server)

(defgroup emacs-everywhere ()
  "Customise group for Emacs-everywhere."
  :group 'convenience)

(define-obsolete-variable-alias
  'emacs-everywhere-paste-p 'emacs-everywhere-paste-command "0.1.0")

(defvar emacs-everywhere--spacehammer-hs (executable-find "hs"))

(defvar emacs-everywhere--display-server
  (cond
   ((eq system-type 'darwin) (if emacs-everywhere--spacehammer-hs 'spacehammer 'quartz))
   ((memq system-type '(ms-dos windows-nt cygwin)) 'windows)
   ((executable-find "loginctl")
    (pcase (string-trim
            (shell-command-to-string "loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p Type")
            "Type=" "\n")
      ("x11" 'x11)
      ("wayland" 'wayland)
      (_ 'unknown)))
   (t 'unknown))
  "The detected display server.")

(defcustom emacs-everywhere-paste-command
  (pcase emacs-everywhere--display-server
    ('spacehammer)
    ('quartz (list "osascript" "-e" "tell application \"System Events\" to keystroke \"v\" using command down"))
    ('x11 (list "xdotool" "key" "--clearmodifiers" "Shift+Insert"))
    ((or 'wayland 'unknown)
     (list "notify-send"
           "No paste command defined for emacs-everywhere"
           "-a" "Emacs" "-i" "emacs")))
  "Command to trigger a system paste from the clipboard.
This is given as a list in the form (CMD ARGS...).

To not run any command, set to nil."
  :type '(set (repeat string) (const nil))
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-window-focus-command
  (pcase emacs-everywhere--display-server
    ('spacehammer (list emacs-everywhere--spacehammer-hs "-c"
                        "require(\"emacs\").switchToAppAndPasteFromClipboard (\"%w\"\)"))
    ('quartz (list "osascript" "-e" "tell application \"%w\" to activate"))
    ('x11 (list "xdotool" "windowactivate" "--sync" "%w")))
  "Command to refocus the active window when emacs-everywhere was triggered.
This is given as a list in the form (CMD ARGS...).
In the arguments, \"%w\" is treated as a placeholder for the window ID,
as returned by `emacs-everywhere-app-id'.

When nil, nothing is executed, and pasting is not attempted."
  :type '(set (repeat string) (const nil))
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-markdown-windows
  '("Zulip" "Stack Exchange" "Stack Overflow" ; Sites
    "^(7) " ; Reddit
    "Pull Request" "Issue" "Comparing .*\\.\\.\\." ; Github
    "Discord")
  "For use with `emacs-everywhere-markdown-p'.
Patterns which are matched against the window title."
  :type '(rep string)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-markdown-apps
  '("Discord" "Element" "Fractal" "NeoChat" "Slack")
  "For use with `emacs-everywhere-markdown-p'.
Patterns which are matched against the app name."
  :type '(rep string)
  :group 'emacs-everywhere)

;; (defcustom emacs-everywhere-latex-windows
;;   '("Inkscape")
;;   "For use with `emacs-everywhere-latex-p'.
;; Patterns which are matched against the window title."
;;   :type '(rep string)
;;   :group 'emacs-everywhere)

;; (defcustom emacs-everywhere-latex-apps
;;   '("Inkscape")
;;   "For use with `emacs-everywhere-latex-p'.
;; Patterns which are matched against the app name."
;;   :type '(rep string)
;;   :group 'emacs-everywhere)

;; (defcustom emacs-everywhere-latex-preamble
;;   "\\documentclass[12pt,border=12pt]{standalone}
;; \\usepackage[utf8]{inputenc}
;; \\usepackage[T1]{fontenc}
;; \\usepackage{textcomp}
;; \\usepackage{amsmath, amssymb}
;; \\newcommand{\\R}{\\mathbb R}
;; \\begin{document}"
;;   "Latex preamble for pdf end result."
;;   :type 'string
;;   :group 'emacs-everywhere)

(defcustom emacs-everywhere-force-use-org-mode nil
  "Whether use `org-mode' as editiong mode or not.
This force to set `org-mode' even if it is markdown flavor site."
  :type 'boolean
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-frame-name-format "Emacs Everywhere :: %s — %s"
  "Format string used to produce the frame name.
Formatted with the app name, and truncated window name."
  :type 'string
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-init-hooks
  '(emacs-everywhere-set-frame-name
    emacs-everywhere-set-frame-position
    emacs-everywhere-major-mode
    emacs-everywhere-insert-selection)
  "Hooks to be run before function `emacs-everywhere-mode'."
  :type 'hook
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-non-init-hooks
  '(emacs-everywhere-set-frame-name
    emacs-everywhere-set-frame-position
    emacs-everywhere-major-mode
    emacs-everywhere-non-insert-selection)
  "Hooks to be run before function `emacs-everywhere-mode'."
  :type 'hook
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-determine-mode-alist
  (list
   (cons (lambda () (and (not emacs-everywhere-force-use-org-mode)
                         (fboundp 'markdown-mode)
                         (emacs-everywhere-markdown-p))) 'markdown-mode)
   ;; (cons (lambda () (and (fboundp 'latex-mode)
   ;;                       (emacs-everywhere-latex-p))) 'latex-mode)
   (cons (lambda () t) #'org-mode))
  "List to determine major mode for emacs-everywhere."
  :type 'list
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-final-hooks
  '(emacs-everywhere-return-converted-org-to-gfm)
  "Hooks to be run just before content is copied."
  :type 'hook
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-frame-parameters
  `((name . "emacs-everywhere")
    (width . 80)
    (height . 12))
  "Parameters `make-frame' recognises to apply to the emacs-everywhere frame."
  :type 'list
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-file-dir
  temporary-file-directory
  "The default directory for temp files generated by `emacs-everywhere-filename-function'."
  :type 'string
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-file-patterns
  (let ((default-directory emacs-everywhere-file-dir))
    (list (concat "^" (regexp-quote (file-truename "emacs-everywhere-")))
          ;; For qutebrowser 'editor.command' support
          (concat "^" (regexp-quote (file-truename "qutebrowser-editor-")))))
  "A list of file regexps to activate `emacs-everywhere-mode' for."
  :type '(repeat regexp)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-finish-delay 0.02
  "Delay for the clipboard contents to be properly set in `emacs-everywhere-finish'."
  :type 'float
  :group 'emacs-everywhere)

;; Semi-internal variables

(defconst emacs-everywhere-osascript-accessibility-error-message
  "osascript is not allowed assistive access"
  "String to search for to determine if Emacs does not have accessibility rights.")

(defvar-local emacs-everywhere-current-app nil
  "The current `emacs-everywhere-app'")
;; Prevents buffer-local variable from being unset by major mode changes
(put 'emacs-everywhere-current-app 'permanent-local t)

(defvar-local emacs-everywhere--contents nil)

;; Make the byte-compiler happier

(declare-function org-in-src-block-p "org")
(declare-function org-ctrl-c-ctrl-c "org")
(declare-function org-export-to-buffer "ox")
(declare-function evil-insert-state "evil-states")
(declare-function spell-fu-buffer "spell-fu")
(declare-function markdown-mode "markdown-mode")

;;; Primary functionality

;;;###autoload
(defun emacs-everywhere (&optional app-info file line column)
  "Lanuch the emacs-everywhere frame from emacsclient."
  (let ((app-info (or app-info (emacs-everywhere-app-info))))
    (apply #'call-process "emacsclient" nil 0 nil
           (delq
            nil (list
                 (when (server-running-p)
                   (if server-use-tcp
                       (concat "--server-file="
                               (shell-quote-argument
                                (expand-file-name server-name server-auth-dir)))
                     (concat "--socket-name="
                             (shell-quote-argument
                              (expand-file-name server-name server-socket-dir)))))
                 "-c" "-F"
                 (prin1-to-string
                  (cons (cons 'emacs-everywhere-app app-info)
                        emacs-everywhere-frame-parameters))
                 (cond ((and line column) (format "+%d:%d" line column))
                       (line              (format "+%d" line)))
                 (or file
                     (expand-file-name
                      (funcall emacs-everywhere-filename-function app-info)
                      emacs-everywhere-file-dir)))))))

(defun emacs-everywhere-file-p (file)
  "Return non-nil if FILE should be handled by emacs-everywhere.
This matches FILE against `emacs-everywhere-file-patterns'."
  (let ((file (file-truename file)))
    (cl-some (lambda (pattern) (string-match-p pattern file))
             emacs-everywhere-file-patterns)))

;;;###autoload
(defun emacs-everywhere-initialise ()
  "Entry point for the executable.
APP is an `emacs-everywhere-app' struct."
  (when-let ((manage? (pcase (file-name-base (buffer-file-name (buffer-base-buffer)))
                        ((pred (string-prefix-p "tmp_"))
                         'tmp)
                        ((pred (emacs-everywhere-file-p))
                         'everywhere)))
             (app (or (frame-parameter nil 'emacs-everywhere-app)
                      (emacs-everywhere-app-info))))
    (setq-local emacs-everywhere-current-app app)
    (if (eq manage? 'everywhere)
        (progn
          (with-demoted-errors "Emacs Everywhere: error running init hooks, %s"
            (run-hooks 'emacs-everywhere-init-hooks))
          (emacs-everywhere-mode 1)
          (setq emacs-everywhere--contents (buffer-string)))
      (with-demoted-errors "Emacs Everywhere: error running init hooks, %s"
        (run-hooks 'emacs-everywhere-non-init-hooks))
      (run-hooks 'emacs-everywhere-mode-hook)
      (dolist (hook emacs-everywhere-final-hooks)
        (add-hook 'before-save-hook hook 90 t)))))

;;;###autoload
(add-hook 'server-visit-hook #'emacs-everywhere-initialise)

(defvar emacs-everywhere-mode-initial-map
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "DEL") #'emacs-everywhere-erase-buffer)
    (define-key keymap (kbd "C-SPC") #'emacs-everywhere-erase-buffer)
    keymap)
  "Transient keymap invoked when an emacs-everywhere buffer is first created.
Set to `nil' to prevent this transient map from activating in emacs-everywhere
buffers.")

(define-minor-mode emacs-everywhere-mode
  "Tweak the current buffer to add some emacs-everywhere considerations."
  :init-value nil
  :keymap `((,(kbd "C-c C-c") . emacs-everywhere-finish-or-ctrl-c-ctrl-c)
            (,(kbd "C-x 5 0") . emacs-everywhere-finish)
            (,(kbd "C-c C-k") . emacs-everywhere-abort))
  ;; line breaking
  (turn-off-auto-fill)
  (visual-line-mode t)
  ;; DEL/C-SPC to clear (first keystroke only)
  (when (keymapp emacs-everywhere-mode-initial-map)
    (set-transient-map emacs-everywhere-mode-initial-map)))

(defun emacs-everywhere-erase-buffer ()
  "Delete the contents of the current buffer."
  (interactive)
  (delete-region (point-min) (point-max)))

(defun emacs-everywhere-finish-or-ctrl-c-ctrl-c ()
  "Finish emacs-everywhere session or invoke `org-ctrl-c-ctrl-c' in org-mode."
  (interactive)
  (if (and (eq major-mode 'org-mode)
           (org-in-src-block-p))
      (org-ctrl-c-ctrl-c)
    (emacs-everywhere-finish)))

(defun emacs-everywhere-finish (&optional abort)
  "Copy buffer content, close emacs-everywhere window, and maybe paste.
Must only be called within a emacs-everywhere buffer.
Never paste content when ABORT is non-nil."
  (interactive)
  (when emacs-everywhere-mode
    (when (equal emacs-everywhere--contents (buffer-string))
      (setq abort t))
    (unless abort
      (run-hooks 'emacs-everywhere-final-hooks)
      (clipboard-kill-ring-save (point-min) (point-max)))
    (unless emacs-everywhere--spacehammer-hs
      (sleep-for 0.01) ; prevents weird multi-second pause, lets clipboard info propagate
      )
    (when emacs-everywhere-window-focus-command
      (let* ((window-id (emacs-everywhere-app-id emacs-everywhere-current-app))
             (window-id-str (if (numberp window-id) (number-to-string window-id) window-id)))
        (apply #'call-process (car emacs-everywhere-window-focus-command)
               nil 0 nil
               (mapcar (lambda (arg)
                         (replace-regexp-in-string "%w" window-id-str arg))
                       (cdr emacs-everywhere-window-focus-command)))
        ;; The frame only has this parameter if this package initialized the temp
        ;; file its displaying. Otherwise, it was created by another program, likely
        ;; a browser with direct EDITOR support, like qutebrowser.
        (when (and (frame-parameter nil 'emacs-everywhere-app)
                   emacs-everywhere-paste-command
                   (not abort))
          (apply #'call-process (car emacs-everywhere-paste-command)
                 nil 0 nil (cdr emacs-everywhere-paste-command)))))
    ;; Clean up after ourselves in case the buffer survives `server-buffer-done'
    ;; (b/c `server-existing-buffer' is non-nil).
    (emacs-everywhere-mode -1)
    (server-buffer-done (current-buffer))))

(defun emacs-everywhere-abort ()
  "Abort current emacs-everywhere session."
  (interactive)
  (set-buffer-modified-p nil)
  (emacs-everywhere-finish t))

;;; Window info

(cl-defstruct emacs-everywhere-app
  "Metadata about the last focused window before emacs-everywhere was invoked."
  id class title)

(defun emacs-everywhere--app-info (id app title)
  "Return information on the active window."
  (make-emacs-everywhere-app
   :id id
   :class app
   :title (replace-regexp-in-string
           (format " ?-[A-Za-z0-9 ]*%s"
                   (regexp-quote app))
           ""
           (replace-regexp-in-string
            "[^[:ascii:]]+" "-" title))))

(defun emacs-everywhere-app-info (&optional id app title)
  "Return information on the active window."
  (let ((w (pcase system-type
             (`darwin (emacs-everywhere-app-info-osx))
             (_ (emacs-everywhere-app-info-linux)))))
    (setf (emacs-everywhere-app-title w)
          (replace-regexp-in-string
           (format " ?-[A-Za-z0-9 ]*%s"
                   (regexp-quote (emacs-everywhere-app-class w)))
           ""
           (replace-regexp-in-string
            "[^[:ascii:]]+" "-" (emacs-everywhere-app-title w))))
    w))

(defun emacs-everywhere-call (command &rest args)
  "Execute COMMAND with ARGS synchronously."
  (with-temp-buffer
    (apply #'call-process command nil t nil (remq nil args))
    (when (and (eq system-type 'darwin)
               (string-match-p emacs-everywhere-osascript-accessibility-error-message (buffer-string)))
      (call-process "osascript" nil nil nil
                        "-e" (format "display alert \"emacs-everywhere\" message \"Emacs has not been granted accessibility permissions, cannot run emacs-everywhere!
Please go to 'System Preferences > Security & Privacy > Privacy > Accessibility' and allow Emacs.\"" ))
      (error "MacOS accessibility error, aborting."))
    (string-trim (buffer-string))))

(defun emacs-everywhere-app-info-linux ()
  "Return information on the active window, on linux."
  (let ((window-id (emacs-everywhere-call "xdotool" "getactivewindow")))
    (let ((app-name
           (car (split-string-and-unquote
                 (string-trim-left
                  (emacs-everywhere-call "xprop" "-id" window-id "WM_CLASS")
                  "[^ ]+ = \"[^\"]+\", "))))
          (window-title
           (car (split-string-and-unquote
                 (string-trim-left
                  (emacs-everywhere-call "xprop" "-id" window-id "_NET_WM_NAME")
                  "[^ ]+ = ")))))
      (make-emacs-everywhere-app
       :id (string-to-number window-id)
       :class app-name
       :title window-title))))

(defvar emacs-everywhere--dir (file-name-directory load-file-name))

(defun emacs-everywhere-app-info-osx ()
  "Return information on the active window, on osx."
  (emacs-everywhere-ensure-oscascript-compiled)
  (let ((default-directory emacs-everywhere--dir))
    (let ((app-name (emacs-everywhere-call
                     "osascript" "app-name"))
          (window-title (emacs-everywhere-call
                         "osascript" "window-title")))
      (make-emacs-everywhere-app
       :id app-name
       :class app-name
       :title window-title))))

(defun emacs-everywhere-ensure-oscascript-compiled (&optional force)
  "Ensure that compiled oscascript files are present.
Will always compile when FORCE is non-nil."
  (unless (and (file-exists-p "app-name")
               (file-exists-p "window-title")
               (not force))
    (let ((default-directory emacs-everywhere--dir)
          (app-name
           "tell application \"System Events\"
    set frontAppName to name of first application process whose frontmost is true
end tell
return frontAppName")
          (window-title
           "set windowTitle to \"\"
tell application \"System Events\"
     set frontAppProcess to first application process whose frontmost is true
end tell
tell frontAppProcess
    if count of windows > 0 then
        set windowTitle to name of front window
    end if
end tell
return windowTitle"))
      (dolist (script `(("app-name" . ,app-name)
                        ("window-title" . ,window-title)))
        (write-region (cdr script) nil (concat (car script) ".applescript"))
        (shell-command (format "osacompile -r scpt:128 -t osas -o %s %s"
                               (car script) (concat (car script) ".applescript")))))))

;;; Secondary functionality

(defun emacs-everywhere-set-frame-name ()
  "Set the frame name based on `emacs-everywhere-frame-name-format'."
  (set-frame-name
   (format emacs-everywhere-frame-name-format
           (emacs-everywhere-app-class emacs-everywhere-current-app)
           (truncate-string-to-width
            (emacs-everywhere-app-title emacs-everywhere-current-app)
            45 nil nil "…"))))

(defun emacs-everywhere-set-frame-position ()
  "Set the size and position of the emacs-everywhere frame."
  (cl-destructuring-bind (x . y) (mouse-absolute-pixel-position)
    (set-frame-position (selected-frame)
                        (- x 100)
                        (- y 50))))

(defun emacs-everywhere-non-insert-selection ()
  (when (and (eq major-mode 'org-mode)
             (emacs-everywhere-markdown-p)
             (executable-find "pandoc"))
    (shell-command-on-region (point-min) (point-max)
                             "pandoc -f markdown-auto_identifiers -t org" nil t)
    (deactivate-mark) (goto-char (point-max))))

(defun emacs-everywhere-insert-selection ()
  "Insert the last text selection into the buffer."
  (cond
   (emacs-everywhere--spacehammer-hs (clipboard-yank))
   ((eq system-type 'darwin)
    (progn
      (call-process "osascript" nil nil nil
                    "-e" "tell application \"System Events\" to keystroke \"c\" using command down")
      (sleep-for 0.01) ; lets clipboard info propagate
      (yank)))
   (_ (when-let ((selection (gui-get-selection 'PRIMARY 'UTF8_STRING)))
        (gui-backend-set-selection 'PRIMARY "")
        (insert selection))))
  (when (and (eq major-mode 'org-mode)
             (emacs-everywhere-markdown-p)
             (executable-find "pandoc"))
    (shell-command-on-region (point-min) (point-max)
                             "pandoc -f markdown-auto_identifiers -t org" nil t)
    (deactivate-mark) (goto-char (point-max)))
  (cond ((bound-and-true-p evil-local-mode) (evil-insert-state))))

(defun emacs-everywhere-markdown-p ()
  "Return t if the original window is recognised as markdown-flavoured."
  (let ((title (emacs-everywhere-app-title emacs-everywhere-current-app))
        (class (emacs-everywhere-app-class emacs-everywhere-current-app)))
    (or (cl-some (lambda (pattern)
                   (string-match-p pattern title))
                 emacs-everywhere-markdown-windows)
        (cl-some (lambda (pattern)
                   (string-match-p pattern class))
                 emacs-everywhere-markdown-apps))))

;; (defun emacs-everywhere-latex-p ()
;;   "Return t if the original window is recognised as markdown-flavoured."
;;   (let ((title (emacs-everywhere-app-title emacs-everywhere-current-app))
;;         (class (emacs-everywhere-app-class emacs-everywhere-current-app)))
;;     (or (cl-some (lambda (pattern)
;;                    (string-match-p pattern title))
;;                  emacs-everywhere-latex-windows)
;;         (cl-some (lambda (pattern)
;;                    (string-match-p pattern class))
;;                  emacs-everywhere-latex-apps))))

(defun emacs-everywhere-major-mode ()
  "Determine major mode based on context."
  (cl-loop for i in emacs-everywhere-determine-mode-alist
           if (funcall (car-safe i)) return (funcall (cdr i))))

(defcustom emacs-everywhere-org-export-options
  "#+property: header-args :exports both
#+options: toc:nil\n"
  "A string inserted at the top of the Org buffer prior to export.
This is with the purpose of setting #+property and #+options parameters.

Should end in a newline to avoid interfering with the buffer content."
  :type 'string
  :group 'emacs-everywhere)

(defvar org-export-show-temporary-export-buffer)
(defun emacs-everywhere-return-converted-org-to-gfm ()
  "When appropriate, convert org buffer to markdown."
  (when (and (eq major-mode 'org-mode)
             (emacs-everywhere-markdown-p))
    (goto-char (point-min))
    (insert emacs-everywhere-org-export-options)
    (let (org-export-show-temporary-export-buffer)
      (require 'ox-md)
      (org-export-to-buffer (if (featurep 'ox-gfm) 'gfm 'md) (current-buffer)))))

;; (defun emacs-everywhere-return-converted-latex-to-svg ()
;;   "When appropriate, convert org buffer to markdown."
;;   (when (emacs-everywhere-latex-p)
;;     (goto-char (point-min))
;;     (insert emacs-everywhere-latex-preamble)
;;     (goto-char (point-max))
;;     (insert "\n\\end{document}")
;;     (save-buffer)
;;     (let ((tname buffer-file-name))
;;       (call-process "pdflatex" nil  nil nil tname)
;;       (call-process "pdf2svg" nil  nil nil (concat tname ".pdf") (concat tname ".svg"))
;;       (erase-buffer)
;;       (insert-file-contents (concat tname ".svg")))))

(provide 'emacs-everywhere)
;;; emacs-everywhere.el ends here
