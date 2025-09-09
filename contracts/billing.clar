;; EV Charging Billing Contract
;; Manages usage-based billing for electric vehicle charging sessions
;; Handles payment processing, rate management, and revenue distribution

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant SECONDS-PER-HOUR u3600)
(define-constant DEFAULT-RATE-PER-KWH u1000000) ;; 0.01 EVT per kWh (8 decimals)
(define-constant MIN-SESSION-DURATION u60) ;; 1 minute minimum
(define-constant MAX-SESSION-DURATION u43200) ;; 12 hours maximum
(define-constant OPERATOR-SHARE u80) ;; 80% to operators
(define-constant PROTOCOL-SHARE u20) ;; 20% to protocol

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-STATION (err u201))
(define-constant ERR-SESSION-NOT-FOUND (err u202))
(define-constant ERR-SESSION-ALREADY-ACTIVE (err u203))
(define-constant ERR-SESSION-NOT-ACTIVE (err u204))
(define-constant ERR-INSUFFICIENT-BALANCE (err u205))
(define-constant ERR-INVALID-AMOUNT (err u206))
(define-constant ERR-PAYMENT-FAILED (err u207))
(define-constant ERR-INVALID-DURATION (err u208))
(define-constant ERR-INVALID-RATE (err u209))
(define-constant ERR-STATION-OFFLINE (err u210))

;; Data Variables
(define-data-var contract-owner principal CONTRACT-OWNER)
(define-data-var protocol-fee-recipient principal CONTRACT-OWNER)
(define-data-var session-counter uint u0)
(define-data-var total-revenue uint u0)
(define-data-var total-sessions uint u0)
(define-data-var emergency-stop bool false)

;; Data Maps

;; Charging sessions
(define-map charging-sessions uint {
  session-id: uint,
  user: principal,
  station-id: uint,
  start-time: uint,
  end-time: (optional uint),
  energy-consumed: uint, ;; in Wh (watt-hours)
  rate-per-kwh: uint, ;; EVT tokens per kWh
  total-cost: uint,
  payment-status: (string-ascii 20), ;; "pending", "paid", "refunded"
  operator-share: uint,
  protocol-share: uint
})

;; Station billing rates
(define-map station-rates uint {
  station-id: uint,
  rate-per-kwh: uint,
  peak-rate-per-kwh: uint, ;; Higher rate during peak hours
  peak-start-hour: uint, ;; Peak hours start (0-23)
  peak-end-hour: uint, ;; Peak hours end (0-23)
  operator: principal,
  last-updated: uint
})

;; User billing history
(define-map user-billing-stats principal {
  total-sessions: uint,
  total-energy-consumed: uint,
  total-spent: uint,
  last-session: (optional uint)
})

;; Station revenue tracking
(define-map station-revenue uint {
  total-revenue: uint,
  total-sessions: uint,
  total-energy-sold: uint,
  pending-withdrawal: uint
})

;; Pending payments (escrow)
(define-map pending-payments uint {
  session-id: uint,
  amount: uint,
  timestamp: uint
})

;; Administrative Functions

;; Set station billing rates
(define-public (set-station-rate (station-id uint) 
                                (rate-per-kwh uint)
                                (peak-rate-per-kwh uint)
                                (peak-start-hour uint)
                                (peak-end-hour uint)
                                (operator principal))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                  (is-eq tx-sender operator)) ERR-NOT-AUTHORIZED)
    (asserts! (> rate-per-kwh u0) ERR-INVALID-RATE)
    (asserts! (> peak-rate-per-kwh u0) ERR-INVALID-RATE)
    (asserts! (< peak-start-hour u24) ERR-INVALID-AMOUNT)
    (asserts! (< peak-end-hour u24) ERR-INVALID-AMOUNT)
    
    ;; Set station rates
    (map-set station-rates station-id {
      station-id: station-id,
      rate-per-kwh: rate-per-kwh,
      peak-rate-per-kwh: peak-rate-per-kwh,
      peak-start-hour: peak-start-hour,
      peak-end-hour: peak-end-hour,
      operator: operator,
      last-updated: stacks-block-height
    })
    
    ;; Initialize station revenue if not exists
    (if (is-none (map-get? station-revenue station-id))
      (map-set station-revenue station-id {
        total-revenue: u0,
        total-sessions: u0,
        total-energy-sold: u0,
        pending-withdrawal: u0
      })
      true
    )
    
    (print {
      type: "station-rate-set",
      station-id: station-id,
      rate-per-kwh: rate-per-kwh,
      peak-rate-per-kwh: peak-rate-per-kwh,
      operator: operator
    })
    
    (ok true)
  )
)

;; Session Management

;; Start charging session
(define-public (start-session (station-id uint) (estimated-energy uint))
  (let ((session-id (+ (var-get session-counter) u1))
        (current-time stacks-block-height)
        (station-rate (unwrap! (map-get? station-rates station-id) ERR-INVALID-STATION)))
    
    (asserts! (not (var-get emergency-stop)) ERR-STATION-OFFLINE)
    (asserts! (> estimated-energy u0) ERR-INVALID-AMOUNT)
    
    ;; Create new session
    (map-set charging-sessions session-id {
      session-id: session-id,
      user: tx-sender,
      station-id: station-id,
      start-time: current-time,
      end-time: none,
      energy-consumed: u0,
      rate-per-kwh: (get rate-per-kwh station-rate),
      total-cost: u0,
      payment-status: "pending",
      operator-share: u0,
      protocol-share: u0
    })
    
    ;; Update session counter
    (var-set session-counter session-id)
    
    ;; Update total sessions
    (var-set total-sessions (+ (var-get total-sessions) u1))
    
    ;; Log session start
    (print {
      type: "session-started",
      session-id: session-id,
      user: tx-sender,
      station-id: station-id,
      start-time: current-time
    })
    
    (ok session-id)
  )
)

;; End charging session and process payment
(define-public (end-session (session-id uint) (energy-consumed uint))
  (let ((session (unwrap! (map-get? charging-sessions session-id) ERR-SESSION-NOT-FOUND))
        (current-time stacks-block-height)
        (station-rate (unwrap! (map-get? station-rates (get station-id session)) ERR-INVALID-STATION))
        (duration (- current-time (get start-time session))))
    
    ;; Validate session ownership and state
    (asserts! (is-eq tx-sender (get user session)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (get end-time session)) ERR-SESSION-NOT-ACTIVE)
    (asserts! (>= duration MIN-SESSION-DURATION) ERR-INVALID-DURATION)
    (asserts! (<= duration MAX-SESSION-DURATION) ERR-INVALID-DURATION)
    (asserts! (> energy-consumed u0) ERR-INVALID-AMOUNT)
    
    ;; Calculate cost based on energy consumption
    (let ((cost-calculation (calculate-session-cost energy-consumed (get rate-per-kwh station-rate)))
          (total-cost (get total-cost cost-calculation))
          (operator-share (get operator-share cost-calculation))
          (protocol-share (get protocol-share cost-calculation)))
      
      ;; Process payment  
      (asserts! (process-payment tx-sender total-cost operator-share protocol-share (get operator station-rate)) ERR-PAYMENT-FAILED)
      
      ;; Update session
      (map-set charging-sessions session-id
        (merge session {
          end-time: (some current-time),
          energy-consumed: energy-consumed,
          total-cost: total-cost,
          payment-status: "paid",
          operator-share: operator-share,
          protocol-share: protocol-share
        })
      )
      
      ;; Update user billing stats
      (update-user-billing-stats tx-sender session-id energy-consumed total-cost)
      
      ;; Update station revenue
      (update-station-revenue (get station-id session) total-cost energy-consumed)
      
      ;; Update global stats
      (var-set total-revenue (+ (var-get total-revenue) total-cost))
      
      ;; Log session completion
      (print {
        type: "session-completed",
        session-id: session-id,
        user: tx-sender,
        station-id: (get station-id session),
        energy-consumed: energy-consumed,
        total-cost: total-cost,
        duration: duration
      })
      
      (ok total-cost)
    )
  )
)

;; Private helper functions

;; Calculate session cost with revenue sharing
(define-private (calculate-session-cost (energy-wh uint) (rate-per-kwh uint))
  (let ((energy-kwh (/ energy-wh u1000)) ;; Convert Wh to kWh
        (total-cost (* energy-kwh rate-per-kwh))
        (operator-share (/ (* total-cost OPERATOR-SHARE) u100))
        (protocol-share (- total-cost operator-share)))
    {
      total-cost: total-cost,
      operator-share: operator-share,
      protocol-share: protocol-share
    }
  )
)

;; Process payment for charging session
(define-private (process-payment (user principal) 
                                (total-cost uint)
                                (operator-share uint)
                                (protocol-share uint)
                                (operator principal))
  (begin
    ;; Transfer total cost from user (commented out for development)
    ;; (try! (contract-call? .token transfer total-cost user (as-contract tx-sender) none))
    
    ;; Distribute to operator (commented out for development)
    ;; (try! (as-contract (contract-call? .token transfer operator-share tx-sender operator none)))
    
    ;; Keep protocol share in contract for now (can be withdrawn later)
    ;; Protocol share stays in contract balance
    
    ;; For development, just return success
    (print { type: "payment-processed", user: user, total-cost: total-cost, operator: operator })
    true ;; Return simple boolean instead of (ok true) to avoid response type issue
  )
)

;; Update user billing statistics
(define-private (update-user-billing-stats (user principal) 
                                         (session-id uint)
                                         (energy-consumed uint)
                                         (total-cost uint))
  (let ((current-stats (default-to {
                                     total-sessions: u0,
                                     total-energy-consumed: u0,
                                     total-spent: u0,
                                     last-session: none
                                   } (map-get? user-billing-stats user))))
    (map-set user-billing-stats user {
      total-sessions: (+ (get total-sessions current-stats) u1),
      total-energy-consumed: (+ (get total-energy-consumed current-stats) energy-consumed),
      total-spent: (+ (get total-spent current-stats) total-cost),
      last-session: (some session-id)
    })
  )
)

;; Update station revenue statistics
(define-private (update-station-revenue (station-id uint) 
                                       (revenue uint)
                                       (energy-sold uint))
  (let ((current-revenue (unwrap-panic (map-get? station-revenue station-id))))
    (map-set station-revenue station-id {
      total-revenue: (+ (get total-revenue current-revenue) revenue),
      total-sessions: (+ (get total-sessions current-revenue) u1),
      total-energy-sold: (+ (get total-energy-sold current-revenue) energy-sold),
      pending-withdrawal: (get pending-withdrawal current-revenue)
    })
  )
)

;; Read-only Functions

;; Get session details
(define-read-only (get-session (session-id uint))
  (map-get? charging-sessions session-id)
)

;; Get station rates
(define-read-only (get-station-rates (station-id uint))
  (map-get? station-rates station-id)
)

;; Get user billing statistics
(define-read-only (get-user-stats (user principal))
  (map-get? user-billing-stats user)
)

;; Get station revenue
(define-read-only (get-station-revenue (station-id uint))
  (map-get? station-revenue station-id)
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-sessions: (var-get total-sessions),
    total-revenue: (var-get total-revenue),
    session-counter: (var-get session-counter),
    emergency-stop: (var-get emergency-stop)
  }
)

;; Calculate estimated cost for energy amount
(define-read-only (estimate-cost (station-id uint) (energy-wh uint))
  (match (map-get? station-rates station-id)
    station-rate (let ((energy-kwh (/ energy-wh u1000))
                       (cost (* energy-kwh (get rate-per-kwh station-rate))))
                   (ok cost))
    ERR-INVALID-STATION
  )
)

;; Administrative Functions

;; Emergency stop (only contract owner)
(define-public (set-emergency-stop (enabled bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set emergency-stop enabled)
    (print { type: "emergency-stop-toggled", enabled: enabled })
    (ok true)
  )
)

;; Withdraw protocol fees (only contract owner)
(define-public (withdraw-protocol-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer protocol fees to fee recipient (commented out for development)
    ;; (try! (as-contract (contract-call? .token transfer amount tx-sender (var-get protocol-fee-recipient) none)))
    
    (print { type: "protocol-fees-withdrawn", amount: amount })
    (ok true)
  )
)

;; Update contract owner (only current owner)
(define-public (update-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (print { type: "contract-owner-updated", new-owner: new-owner })
    (ok true)
  )
)

