;; EV Charging Access Control Contract
;; Manages charging station registration, user authentication, and access permissions
;; Controls who can use which stations and tracks station status

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant STATION-REGISTRATION-FEE u1000000000) ;; 10 EVT tokens
(define-constant MAX-STATIONS-PER-OPERATOR u100)
(define-constant MIN-STATION-POWER u3500) ;; 3.5 kW minimum
(define-constant MAX-STATION-POWER u350000) ;; 350 kW maximum (DC fast charging)

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-STATION-NOT-FOUND (err u301))
(define-constant ERR-STATION-ALREADY-EXISTS (err u302))
(define-constant ERR-STATION-OFFLINE (err u303))
(define-constant ERR-USER-BANNED (err u304))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u305))
(define-constant ERR-INVALID-POWER-RATING (err u306))
(define-constant ERR-MAX-STATIONS-EXCEEDED (err u307))
(define-constant ERR-STATION-OCCUPIED (err u308))
(define-constant ERR-INVALID-LOCATION (err u309))
(define-constant ERR-MAINTENANCE-MODE (err u310))

;; Data Variables
(define-data-var contract-owner principal CONTRACT-OWNER)
(define-data-var station-counter uint u0)
(define-data-var total-registered-stations uint u0)
(define-data-var registration-fee uint STATION-REGISTRATION-FEE)
(define-data-var system-maintenance bool false)

;; Data Maps

;; Charging station registry
(define-map charging-stations uint {
  station-id: uint,
  operator: principal,
  location: (string-utf8 100),
  power-rating: uint, ;; in watts
  station-type: (string-ascii 20), ;; "AC", "DC-Fast", "Supercharger"
  status: (string-ascii 20), ;; "online", "offline", "maintenance", "occupied"
  registration-time: uint,
  last-heartbeat: uint,
  total-sessions: uint,
  connector-types: (list 5 (string-ascii 20)), ;; ["CCS", "CHAdeMO", "Type2"]
  pricing-tier: (string-ascii 10) ;; "basic", "premium", "ultra"
})

;; Station operators
(define-map station-operators principal {
  operator: principal,
  registration-time: uint,
  total-stations: uint,
  active-stations: uint,
  reputation-score: uint, ;; 0-100
  verified: bool,
  contact-info: (optional (string-utf8 100))
})

;; User access permissions
(define-map user-permissions principal {
  user: principal,
  registration-time: uint,
  access-level: (string-ascii 20), ;; "basic", "premium", "vip"
  banned: bool,
  total-sessions: uint,
  last-activity: uint,
  banned-until: (optional uint)
})

;; Station access logs
(define-map access-logs { station-id: uint, user: principal, timestamp: uint } {
  session-id: (optional uint),
  access-granted: bool,
  reason: (string-ascii 50)
})

;; Active sessions tracking
(define-map active-sessions uint {
  station-id: uint,
  user: principal,
  session-start: uint,
  estimated-end: uint
})

;; Operator station mapping
(define-map operator-stations { operator: principal, station-index: uint } uint)

;; Station Management Functions

;; Register new charging station
(define-public (register-station (location (string-utf8 100))
                                (power-rating uint)
                                (station-type (string-ascii 20))
                                (connector-types (list 5 (string-ascii 20)))
                                (pricing-tier (string-ascii 10)))
  (let ((station-id (+ (var-get station-counter) u1))
        (current-time stacks-block-height)
        (operator-info (default-to {
                                     operator: tx-sender,
                                     registration-time: current-time,
                                     total-stations: u0,
                                     active-stations: u0,
                                     reputation-score: u75,
                                     verified: false,
                                     contact-info: none
                                   } (map-get? station-operators tx-sender))))
    
    (asserts! (not (var-get system-maintenance)) ERR-MAINTENANCE-MODE)
    (asserts! (>= power-rating MIN-STATION-POWER) ERR-INVALID-POWER-RATING)
    (asserts! (<= power-rating MAX-STATION-POWER) ERR-INVALID-POWER-RATING)
    (asserts! (< (get total-stations operator-info) MAX-STATIONS-PER-OPERATOR) ERR-MAX-STATIONS-EXCEEDED)
    (asserts! (> (len location) u0) ERR-INVALID-LOCATION)
    
    ;; Pay registration fee (commented out for development)
    ;; (try! (contract-call? .token transfer (var-get registration-fee) tx-sender (as-contract tx-sender) none))
    
    ;; Register the station
    (map-set charging-stations station-id {
      station-id: station-id,
      operator: tx-sender,
      location: location,
      power-rating: power-rating,
      station-type: station-type,
      status: "offline",
      registration-time: current-time,
      last-heartbeat: current-time,
      total-sessions: u0,
      connector-types: connector-types,
      pricing-tier: pricing-tier
    })
    
    ;; Update operator info
    (map-set station-operators tx-sender
      (merge operator-info {
        total-stations: (+ (get total-stations operator-info) u1)
      })
    )
    
    ;; Add to operator station mapping
    (map-set operator-stations { operator: tx-sender, station-index: (get total-stations operator-info) } station-id)
    
    ;; Update global counters
    (var-set station-counter station-id)
    (var-set total-registered-stations (+ (var-get total-registered-stations) u1))
    
    ;; Log registration
    (print {
      type: "station-registered",
      station-id: station-id,
      operator: tx-sender,
      location: location,
      power-rating: power-rating,
      station-type: station-type
    })
    
    (ok station-id)
  )
)

;; Update station status (operators only)
(define-public (update-station-status (station-id uint) (status (string-ascii 20)))
  (let ((station (unwrap! (map-get? charging-stations station-id) ERR-STATION-NOT-FOUND)))
    
    (asserts! (is-eq tx-sender (get operator station)) ERR-NOT-AUTHORIZED)
    
    ;; Update station status and heartbeat
    (map-set charging-stations station-id
      (merge station {
        status: status,
        last-heartbeat: stacks-block-height
      })
    )
    
    ;; Update operator active stations count
    (let ((operator-info (unwrap-panic (map-get? station-operators tx-sender)))
          (status-change (if (is-eq status "online") 1 -1)))
      (if (or (is-eq status "online") (is-eq (get status station) "online"))
        (map-set station-operators tx-sender
          (merge operator-info {
            active-stations: (if (is-eq status "online")
                               (+ (get active-stations operator-info) u1)
                               (if (> (get active-stations operator-info) u0)
                                 (- (get active-stations operator-info) u1)
                                 u0))
          })
        )
        true
      )
    )
    
    (print {
      type: "station-status-updated",
      station-id: station-id,
      status: status,
      timestamp: stacks-block-height
    })
    
    (ok true)
  )
)

;; User Management Functions

;; Register user for access
(define-public (register-user (access-level (string-ascii 20)))
  (let ((current-time stacks-block-height))
    
    (asserts! (is-none (map-get? user-permissions tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get system-maintenance)) ERR-MAINTENANCE-MODE)
    
    ;; Create user permissions
    (map-set user-permissions tx-sender {
      user: tx-sender,
      registration-time: current-time,
      access-level: access-level,
      banned: false,
      total-sessions: u0,
      last-activity: current-time,
      banned-until: none
    })
    
    (print {
      type: "user-registered",
      user: tx-sender,
      access-level: access-level,
      timestamp: current-time
    })
    
    (ok true)
  )
)

;; Access Control Functions

;; Request access to charging station
(define-public (request-access (station-id uint) (estimated-duration uint))
  (let ((station (unwrap! (map-get? charging-stations station-id) ERR-STATION-NOT-FOUND))
        (user-perms (unwrap! (map-get? user-permissions tx-sender) ERR-NOT-AUTHORIZED))
        (current-time stacks-block-height))
    
    ;; Validate access conditions
    (asserts! (not (var-get system-maintenance)) ERR-MAINTENANCE-MODE)
    (asserts! (not (get banned user-perms)) ERR-USER-BANNED)
    (asserts! (is-eq (get status station) "online") ERR-STATION-OFFLINE)
    (asserts! (is-none (map-get? active-sessions station-id)) ERR-STATION-OCCUPIED)
    
    ;; Check if user is banned temporarily
    (match (get banned-until user-perms)
      ban-time (asserts! (> current-time ban-time) ERR-USER-BANNED)
      true
    )
    
    ;; Grant access and create active session
    (map-set active-sessions station-id {
      station-id: station-id,
      user: tx-sender,
      session-start: current-time,
      estimated-end: (+ current-time estimated-duration)
    })
    
    ;; Update station status to occupied
    (map-set charging-stations station-id
      (merge station { status: "occupied" })
    )
    
    ;; Update user activity
    (map-set user-permissions tx-sender
      (merge user-perms {
        last-activity: current-time,
        total-sessions: (+ (get total-sessions user-perms) u1)
      })
    )
    
    ;; Update station session count
    (map-set charging-stations station-id
      (merge station {
        total-sessions: (+ (get total-sessions station) u1)
      })
    )
    
    ;; Log access
    (map-set access-logs { station-id: station-id, user: tx-sender, timestamp: current-time } {
      session-id: none,
      access-granted: true,
      reason: "access-granted"
    })
    
    (print {
      type: "access-granted",
      station-id: station-id,
      user: tx-sender,
      estimated-duration: estimated-duration,
      timestamp: current-time
    })
    
    (ok true)
  )
)

;; Release access from charging station
(define-public (release-access (station-id uint))
  (let ((active-session (unwrap! (map-get? active-sessions station-id) ERR-STATION-NOT-FOUND))
        (station (unwrap! (map-get? charging-stations station-id) ERR-STATION-NOT-FOUND)))
    
    (asserts! (is-eq tx-sender (get user active-session)) ERR-NOT-AUTHORIZED)
    
    ;; Remove active session
    (map-delete active-sessions station-id)
    
    ;; Update station status back to online
    (map-set charging-stations station-id
      (merge station { status: "online" })
    )
    
    ;; Log access release
    (print {
      type: "access-released",
      station-id: station-id,
      user: tx-sender,
      session-duration: (- stacks-block-height (get session-start active-session)),
      timestamp: stacks-block-height
    })
    
    (ok true)
  )
)

;; Administrative Functions

;; Ban user (contract owner or station operators)
(define-public (ban-user (user principal) (duration uint) (reason (string-ascii 50)))
  (let ((user-perms (unwrap! (map-get? user-permissions user) ERR-NOT-AUTHORIZED))
        (ban-until (if (> duration u0) (some (+ stacks-block-height duration)) none)))
    
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    ;; Update user permissions
    (map-set user-permissions user
      (merge user-perms {
        banned: (is-some ban-until),
        banned-until: ban-until
      })
    )
    
    ;; Force release any active sessions
    (let ((stations-to-check (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10))) ;; Check first 10 stations
      (map force-release-user-session stations-to-check)
    )
    
    (print {
      type: "user-banned",
      user: user,
      duration: duration,
      reason: reason,
      banned-until: ban-until
    })
    
    (ok true)
  )
)

;; Helper function to force release user sessions
(define-private (force-release-user-session (station-id uint))
  (match (map-get? active-sessions station-id)
    session (if (is-eq (get user session) tx-sender)
              (begin
                (map-delete active-sessions station-id)
                (match (map-get? charging-stations station-id)
                  station (map-set charging-stations station-id
                                 (merge station { status: "online" }))
                  false
                )
                true
              )
              false)
    false
  )
)

;; Update system maintenance mode (contract owner only)
(define-public (set-maintenance-mode (enabled bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set system-maintenance enabled)
    (print { type: "maintenance-mode-toggled", enabled: enabled })
    (ok true)
  )
)

;; Read-only Functions

;; Get charging station info
(define-read-only (get-station (station-id uint))
  (map-get? charging-stations station-id)
)

;; Get user permissions
(define-read-only (get-user-permissions (user principal))
  (map-get? user-permissions user)
)

;; Get station operator info
(define-read-only (get-operator-info (operator principal))
  (map-get? station-operators operator)
)

;; Get active session for station
(define-read-only (get-active-session (station-id uint))
  (map-get? active-sessions station-id)
)

;; Check if user can access station
(define-read-only (can-access-station (user principal) (station-id uint))
  (match (map-get? user-permissions user)
    user-perms (match (map-get? charging-stations station-id)
                 station (and
                          (not (get banned user-perms))
                          (is-eq (get status station) "online")
                          (is-none (map-get? active-sessions station-id))
                          (not (var-get system-maintenance)))
                 false)
    false
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-stations: (var-get total-registered-stations),
    station-counter: (var-get station-counter),
    registration-fee: (var-get registration-fee),
    maintenance-mode: (var-get system-maintenance)
  }
)

;; Get stations by operator
(define-read-only (get-operator-stations (operator principal))
  (match (map-get? station-operators operator)
    operator-info (let ((station-count (get total-stations operator-info)))
                    (ok (map get-operator-station-id (generate-indices station-count))))
    (err "Operator not found")
  )
)

;; Helper function to generate indices
(define-private (generate-indices (count uint))
  ;; Simplified - in production would generate list up to count
  (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
)

;; Helper function to get operator station ID
(define-private (get-operator-station-id (index uint))
  (default-to u0 (map-get? operator-stations { operator: tx-sender, station-index: index }))
)

;; Update registration fee (contract owner only)
(define-public (update-registration-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set registration-fee new-fee)
    (print { type: "registration-fee-updated", new-fee: new-fee })
    (ok true)
  )
)

;; Transfer contract ownership (contract owner only)
(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (print { type: "contract-ownership-transferred", new-owner: new-owner })
    (ok true)
  )
)

