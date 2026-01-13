;;; zemacs-client.el --- MCP Client for ZEMACS

;; This configuration provides a full-featured client for ZEMACS,
;; including bi-directional JSON-RPC support to handle server-initiated requests
;; (like user prompts) and commands for all implemented tools.

(require 'json)

(defgroup zemacs nil
  "ZEMACS MCP Integration"
  :group 'tools)

(defcustom zemacs-binary-path (expand-file-name "~/Project/zemacs/zig-out/bin/zemacs")
  "Path to the ZEMACS binary."
  :type 'file
  :group 'zemacs)

(defvar zemacs-process-buffer-name "*zemacs*")
(defvar zemacs-process-name "zemacs-process")
(defvar zemacs--buffer-string "")  ; Accumulator for incomplete JSON lines

;; ---------------------------------------------------------------------
;; Core Process & Transport
;; ---------------------------------------------------------------------

(defun zemacs-start ()
  "Start the ZEMACS MCP server process."
  (interactive)
  (if (get-process zemacs-process-name)
      (message "ZEMACS is already running.")
    (message "Starting ZEMACS from %s..." zemacs-binary-path)
    (let ((proc (start-process zemacs-process-name zemacs-process-buffer-name zemacs-binary-path)))
      (set-process-filter proc 'zemacs--filter)
      (set-process-sentinel proc 'zemacs--sentinel)
      ;; Initialize accumulator
      (setq zemacs--buffer-string "")
      (message "ZEMACS started."))))

(defun zemacs-stop ()
  "Stop the ZEMACS server."
  (interactive)
  (let ((proc (get-process zemacs-process-name)))
    (when proc
      (delete-process proc)
      (message "ZEMACS stopped."))))

(defun zemacs--sentinel (proc event)
  (message "ZEMACS Process: %s" event))

(defun zemacs--filter (proc string)
  "Process output from ZEMACS (JSON-RPC messages)."
  (setq zemacs--buffer-string (concat zemacs--buffer-string string))
  (while (string-match "\n" zemacs--buffer-string)
    (let ((line (substring zemacs--buffer-string 0 (match-beginning 0))))
      (setq zemacs--buffer-string (substring zemacs--buffer-string (match-end 0)))
      (unless (string-empty-p line)
        (condition-case err
            (let ((msg (json-read-from-string line)))
              (zemacs--handle-message msg))
          (error (message "ZEMACS JSON Error: %s in line: %s" err line)))))))

(defun zemacs--handle-message (msg)
  "Dispatch incoming JSON-RPC message."
  (let ((id (cdr (assoc 'id msg)))
        (method (cdr (assoc 'method msg)))
        (result (cdr (assoc 'result msg)))
        (error-obj (cdr (assoc 'error msg))) ; 'error' is a keyword in assoc if not careful, checking key
        (params (cdr (assoc 'params msg))))
    
    (cond
     ;; 1. Request from Server (e.g. ask_user)
     (method
      (cond
       ((string= method "zemacs/ask_user")
        (zemacs--handle-ask-user id params))
       (t
        (message "ZEMACS Unknown Request: %s" method))))
     
     ;; 2. Response (Result or Error)
     (t
      (if (assoc 'error msg)
          (message "ZEMACS Error: %s" (cdr (assoc 'message (cdr (assoc 'error msg)))))
        ;; For now, just print non-empty results to minibuffer
        (when result
          (message "ZEMACS: %s" (json-encode result))))))))

(defun zemacs--handle-ask-user (id params)
  "Handle 'zemacs/ask_user' request."
  (let* ((prompt (cdr (assoc 'prompt params)))
         (user-input (read-string (format "ZEMACS Question: %s " prompt))))
    (zemacs--send-response id user-input)))

(defun zemacs--send-response (id result)
  "Send a JSON-RPC Response back to ZEMACS."
  (let ((json-str (json-encode `((jsonrpc . "2.0")
                                 (id . ,id)
                                 (result . ,result)))))
    (zemacs--send-string json-str)))

(defun zemacs--send-string (str)
  (let ((proc (get-process zemacs-process-name)))
    (if (process-live-p proc)
        (process-send-string proc (concat str "\n"))
      (error "ZEMACS not running"))))

(defun zemacs-call (method params)
  "Send a JSON-RPC Request to ZEMACS."
  ;; We use a random ID for simplicity (Emacs integers are small, use high range)
  (let* ((id (random 100000))
         (json-str (json-encode `((jsonrpc . "2.0")
                                  (id . ,id)
                                  (method . ,method)
                                  (params . ,params)))))
    (zemacs--send-string json-str)))

;; ---------------------------------------------------------------------
;; Interactive Commands
;; ---------------------------------------------------------------------

(defun zemacs-status ()
  "Check ZEMACS status."
  (interactive)
  (zemacs-call "tools/call" 
               '((name . "zemacs.status") (arguments . ()))))

(defun zemacs-health ()
  (interactive)
  (zemacs-call "tools/call" '((name . "zemacs.health") (arguments . ()))))

(defun zemacs-exec (command args)
  "Execute a command via ZEMACS."
  (interactive "sCommand: \nsArgs (space separated): ")
  (let ((arg-list (split-string args)))
    (zemacs-call "tools/call"
                 `((name . "exec.run")
                   (arguments . ((command . ,command)
                                 (args . ,arg-list)))))))

(defun zemacs-git-status ()
  (interactive)
  (zemacs-call "tools/call" '((name . "git.status") (arguments . ()))))

(defun zemacs-fs-write (path content)
  "Write file via ZEMACS."
  (interactive "fPath: \nsContent: ")
  (zemacs-call "tools/call"
               `((name . "fs.write")
                 (arguments . ((path . ,(expand-file-name path))
                               (content . ,content))))))

(defun zemacs-tree ()
  (interactive)
  (zemacs-call "tools/call" '((name . "search.project_tree") (arguments . ((path . "."))))))

(provide 'zemacs-client)
