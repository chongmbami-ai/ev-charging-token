;; EV Charging Token Contract (SIP-010 Compliant)
;; A fungible token for the EV charging ecosystem
;; Enables pay-per-use charging with tokenized payments

;; SIP-010 Trait (commented out for development - enable for production)
;; (impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; Token Definition
(define-fungible-token ev-token)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant TOKEN-NAME "EV Charging Token")
(define-constant TOKEN-SYMBOL "EVT")
(define-constant TOKEN-DECIMALS u8)
(define-constant INITIAL-SUPPLY u1000000000000000) ;; 100 million tokens with 8 decimals

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-TRANSFER-FAILED (err u103))
(define-constant ERR-MINTING-DISABLED (err u104))
(define-constant ERR-BURNING-DISABLED (err u105))
(define-constant ERR-INVALID-RECIPIENT (err u106))

;; Data Variables
(define-data-var contract-owner principal CONTRACT-OWNER)
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var minting-enabled bool true)
(define-data-var burning-enabled bool true)
(define-data-var total-minted uint u0)
(define-data-var total-burned uint u0)

;; Data Maps
(define-map token-balances principal uint)
(define-map allowances { owner: principal, spender: principal } uint)
(define-map authorized-minters principal bool)
(define-map authorized-burners principal bool)

;; Initialize contract with initial token supply
(begin
  (try! (ft-mint? ev-token INITIAL-SUPPLY (var-get contract-owner)))
  (var-set total-minted INITIAL-SUPPLY)
)

;; SIP-010 Required Functions

;; Transfer tokens from sender to recipient
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    ;; Check authorization
    (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq sender recipient)) ERR-INVALID-RECIPIENT)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Execute transfer
    (match (ft-transfer? ev-token amount sender recipient)
      success (begin
        ;; Log transfer event
        (print {
          type: "transfer",
          token: TOKEN-NAME,
          amount: amount,
          sender: sender,
          recipient: recipient,
          memo: memo
        })
        (ok true)
      )
      error ERR-TRANSFER-FAILED
    )
  )
)

;; Get token name
(define-read-only (get-name)
  (ok TOKEN-NAME)
)

;; Get token symbol  
(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

;; Get token balance for a principal
(define-read-only (get-balance (who principal))
  (ok (ft-get-balance ev-token who))
)

;; Get total token supply
(define-read-only (get-total-supply)
  (ok (ft-get-supply ev-token))
)

;; Get token URI
(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

;; Administrative Functions

;; Mint new tokens (only authorized minters)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                  (default-to false (map-get? authorized-minters tx-sender))) ERR-NOT-AUTHORIZED)
    (asserts! (var-get minting-enabled) ERR-MINTING-DISABLED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Mint tokens
    (try! (ft-mint? ev-token amount recipient))
    
    ;; Update total minted
    (var-set total-minted (+ (var-get total-minted) amount))
    
    ;; Log mint event
    (print {
      type: "mint",
      token: TOKEN-NAME,
      amount: amount,
      recipient: recipient,
      minter: tx-sender
    })
    
    (ok true)
  )
)

;; Burn tokens from sender (only authorized burners or token holders)
(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (or (is-eq tx-sender owner)
                  (is-eq tx-sender (var-get contract-owner))
                  (default-to false (map-get? authorized-burners tx-sender))) ERR-NOT-AUTHORIZED)
    (asserts! (var-get burning-enabled) ERR-BURNING-DISABLED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Burn tokens
    (try! (ft-burn? ev-token amount owner))
    
    ;; Update total burned
    (var-set total-burned (+ (var-get total-burned) amount))
    
    ;; Log burn event
    (print {
      type: "burn",
      token: TOKEN-NAME,
      amount: amount,
      owner: owner,
      burner: tx-sender
    })
    
    (ok true)
  )
)

;; Set token URI (only contract owner)
(define-public (set-token-uri (uri (string-utf8 256)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set token-uri (some uri))
    (print { type: "token-uri-updated", uri: uri })
    (ok true)
  )
)

;; Authorization Management

;; Add authorized minter (only contract owner)
(define-public (add-minter (minter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set authorized-minters minter true)
    (print { type: "minter-added", minter: minter })
    (ok true)
  )
)

;; Remove authorized minter (only contract owner)
(define-public (remove-minter (minter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-delete authorized-minters minter)
    (print { type: "minter-removed", minter: minter })
    (ok true)
  )
)

;; Add authorized burner (only contract owner)
(define-public (add-burner (burner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set authorized-burners burner true)
    (print { type: "burner-added", burner: burner })
    (ok true)
  )
)

;; Remove authorized burner (only contract owner)
(define-public (remove-burner (burner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-delete authorized-burners burner)
    (print { type: "burner-removed", burner: burner })
    (ok true)
  )
)

;; Control Functions

;; Toggle minting (only contract owner)
(define-public (toggle-minting (enabled bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set minting-enabled enabled)
    (print { type: "minting-toggled", enabled: enabled })
    (ok true)
  )
)

;; Toggle burning (only contract owner)
(define-public (toggle-burning (enabled bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set burning-enabled enabled)
    (print { type: "burning-toggled", enabled: enabled })
    (ok true)
  )
)

;; Transfer contract ownership (only current owner)
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (print { type: "ownership-transferred", old-owner: tx-sender, new-owner: new-owner })
    (ok true)
  )
)

;; Read-only Helper Functions

;; Check if principal is authorized minter
(define-read-only (is-minter (who principal))
  (default-to false (map-get? authorized-minters who))
)

;; Check if principal is authorized burner
(define-read-only (is-burner (who principal))
  (default-to false (map-get? authorized-burners who))
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Get total minted tokens
(define-read-only (get-total-minted)
  (var-get total-minted)
)

;; Get total burned tokens
(define-read-only (get-total-burned)
  (var-get total-burned)
)

;; Check if minting is enabled
(define-read-only (is-minting-enabled)
  (var-get minting-enabled)
)

;; Check if burning is enabled
(define-read-only (is-burning-enabled)
  (var-get burning-enabled)
)

;; Get token info
(define-read-only (get-token-info)
  {
    name: TOKEN-NAME,
    symbol: TOKEN-SYMBOL,
    decimals: TOKEN-DECIMALS,
    total-supply: (ft-get-supply ev-token),
    total-minted: (var-get total-minted),
    total-burned: (var-get total-burned),
    minting-enabled: (var-get minting-enabled),
    burning-enabled: (var-get burning-enabled),
    contract-owner: (var-get contract-owner)
  }
)

