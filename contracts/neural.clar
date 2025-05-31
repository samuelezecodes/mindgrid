;; MindGrid - Neural Mental Health Support Protocol
;; Advanced decentralized support infrastructure with intelligent resource allocation

;; System Error Codes
(define-constant ERR-ADMIN-UNAUTHORIZED (err u100))
(define-constant ERR-NODE-DUPLICATE (err u101))
(define-constant ERR-NODE-NOT-FOUND (err u102))
(define-constant ERR-POOL-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-STAKE-BELOW-THRESHOLD (err u104))
(define-constant ERR-PROTOCOL-OFFLINE (err u105))
(define-constant ERR-INVALID-PAYLOAD (err u106))
(define-constant ERR-INVALID-STATUS-CODE (err u107))
(define-constant ERR-INVALID-OPERATOR (err u108))
(define-constant ERR-CHECKPOINT-NOT-READY (err u109))

;; Protocol Core Variables
(define-data-var protocol-operator principal tx-sender)
(define-data-var liquidity-pool uint u0)
(define-data-var protocol-active bool true)
(define-data-var minimum-stake uint u1000000) ;; 1 STX
(define-data-var emergency-halt bool false)
(define-data-var network-nodes-count uint u0)

;; Network Data Structures
(define-map support-nodes 
    principal 
    {
        node-online: bool,
        resources-allocated: uint,
        last-sync-block: uint,
        node-tier: (string-ascii 20),
        performance-score: uint
    }
)

(define-map liquidity-providers
    principal
    {
        total-staked: uint,
        last-stake-block: uint,
        compute-credits: uint
    }
)

(define-map node-metrics
    principal
    {
        wellness-checkpoints: uint,
        network-connections: uint,
        protocol-uptime: uint
    }
)

;; Protocol Query Functions
(define-read-only (get-protocol-operator)
    (var-get protocol-operator)
)

(define-read-only (get-liquidity-pool)
    (var-get liquidity-pool)
)

(define-read-only (get-support-node-data (node-address principal))
    (map-get? support-nodes node-address)
)

(define-read-only (get-provider-data (provider principal))
    (map-get? liquidity-providers provider)
)

(define-read-only (get-node-metrics (node-address principal))
    (map-get? node-metrics node-address)
)

(define-read-only (get-protocol-status)
    (and (var-get protocol-active) (not (var-get emergency-halt)))
)

(define-read-only (get-network-size)
    (var-get network-nodes-count)
)

;; Internal Protocol Functions
(define-private (verify-operator-access)
    (is-eq tx-sender (var-get protocol-operator))
)

(define-private (update-provider-metrics (provider principal) (stake-amount uint))
    (let (
        (current-data (default-to 
            { total-staked: u0, last-stake-block: u0, compute-credits: u0 } 
            (map-get? liquidity-providers provider)
        ))
    )
    (map-set liquidity-providers
        provider
        {
            total-staked: (+ (get total-staked current-data) stake-amount),
            last-stake-block: block-height,
            compute-credits: (+ (get compute-credits current-data) (/ stake-amount u50000))
        }
    ))
)

;; Validation Layer
(define-private (validate-stake-amount (amount uint))
    (and 
        (> amount u0)
        (<= amount u10000000000000)
    )
)

(define-private (validate-node-tier (tier (string-ascii 20)))
    (or 
        (is-eq tier "alpha")
        (is-eq tier "beta")
        (is-eq tier "gamma")
        (is-eq tier "omega")
        (is-eq tier "archived")
    )
)

(define-private (validate-operator-address (address principal))
    (and 
        (not (is-eq address (var-get protocol-operator)))
        (not (is-eq address (as-contract tx-sender)))
    )
)

;; Core Protocol Functions
(define-public (stake-liquidity)
    (let (
        (stake-amount (stx-get-balance tx-sender))
    )
    (asserts! (>= stake-amount (var-get minimum-stake)) ERR-STAKE-BELOW-THRESHOLD)
    (asserts! (get-protocol-status) ERR-PROTOCOL-OFFLINE)
    
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (var-set liquidity-pool (+ (var-get liquidity-pool) stake-amount))
    (update-provider-metrics tx-sender stake-amount)
    (ok stake-amount))
)

(define-public (register-support-node (node-address principal))
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (asserts! (is-none (map-get? support-nodes node-address)) ERR-NODE-DUPLICATE)
        
        (map-set support-nodes 
            node-address
            {
                node-online: true,
                resources-allocated: u0,
                last-sync-block: u0,
                node-tier: "beta",
                performance-score: u0
            }
        )
        
        ;; Initialize node metrics
        (map-set node-metrics
            node-address
            {
                wellness-checkpoints: u0,
                network-connections: u0,
                protocol-uptime: u0
            }
        )
        
        (var-set network-nodes-count (+ (var-get network-nodes-count) u1))
        (ok true)
    )
)

(define-public (allocate-resources (node-address principal) (resource-amount uint))
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (asserts! (get-protocol-status) ERR-PROTOCOL-OFFLINE)
        (asserts! (>= (var-get liquidity-pool) resource-amount) ERR-POOL-INSUFFICIENT-BALANCE)
        (asserts! 
            (is-some (map-get? support-nodes node-address)) 
            ERR-NODE-NOT-FOUND
        )
        
        (try! (as-contract (stx-transfer? resource-amount tx-sender node-address)))
        (var-set liquidity-pool (- (var-get liquidity-pool) resource-amount))
        
        (let (
            (node-data (unwrap! (map-get? support-nodes node-address) ERR-NODE-NOT-FOUND))
        )
        (map-set support-nodes
            node-address
            {
                node-online: (get node-online node-data),
                resources-allocated: (+ (get resources-allocated node-data) resource-amount),
                last-sync-block: block-height,
                node-tier: (get node-tier node-data),
                performance-score: (get performance-score node-data)
            }
        )
        (ok resource-amount))
    )
)

;; NEW FUNCTION: Record Performance Checkpoint
(define-public (record-checkpoint (node-address principal) (checkpoint-type (string-ascii 20)))
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (asserts! 
            (is-some (map-get? support-nodes node-address)) 
            ERR-NODE-NOT-FOUND
        )
        
        (let (
            (current-metrics (default-to 
                { wellness-checkpoints: u0, network-connections: u0, protocol-uptime: u0 }
                (map-get? node-metrics node-address)
            ))
            (node-data (unwrap! (map-get? support-nodes node-address) ERR-NODE-NOT-FOUND))
        )
        
        ;; Update metrics based on checkpoint type
        (map-set node-metrics
            node-address
            (if (is-eq checkpoint-type "wellness")
                (merge current-metrics { wellness-checkpoints: (+ (get wellness-checkpoints current-metrics) u1) })
                (if (is-eq checkpoint-type "network")
                    (merge current-metrics { network-connections: (+ (get network-connections current-metrics) u1) })
                    (if (is-eq checkpoint-type "uptime")
                        (merge current-metrics { protocol-uptime: (+ (get protocol-uptime current-metrics) u1) })
                        current-metrics
                    )
                )
            )
        )
        
        ;; Update node performance score
        (map-set support-nodes
            node-address
            {
                node-online: (get node-online node-data),
                resources-allocated: (get resources-allocated node-data),
                last-sync-block: (get last-sync-block node-data),
                node-tier: (get node-tier node-data),
                performance-score: (+ (get performance-score node-data) u10)
            }
        )
        
        (ok true))
    )
)

;; Protocol Administration
(define-public (configure-minimum-stake (new-threshold uint))
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (asserts! (validate-stake-amount new-threshold) ERR-INVALID-PAYLOAD)
        (var-set minimum-stake new-threshold)
        (ok true)
    )
)

(define-public (toggle-protocol-status)
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (var-set protocol-active (not (var-get protocol-active)))
        (ok true)
    )
)

(define-public (engage-emergency-halt)
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (var-set emergency-halt true)
        (ok true)
    )
)

(define-public (disengage-emergency-halt)
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (var-set emergency-halt false)
        (ok true)
    )
)

(define-public (update-node-tier (node-address principal) (new-tier (string-ascii 20)))
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (asserts! (validate-node-tier new-tier) ERR-INVALID-STATUS-CODE)
        (asserts! 
            (is-some (map-get? support-nodes node-address)) 
            ERR-NODE-NOT-FOUND
        )
        
        (let (
            (current-node (unwrap! (map-get? support-nodes node-address) ERR-NODE-NOT-FOUND))
        )
        (map-set support-nodes
            node-address
            {
                node-online: (get node-online current-node),
                resources-allocated: (get resources-allocated current-node),
                last-sync-block: (get last-sync-block current-node),
                node-tier: new-tier,
                performance-score: (get performance-score current-node)
            }
        )
        (ok true))
    )
)

;; Operator Transfer Protocol
(define-public (transfer-operator-role (new-operator principal))
    (begin
        (asserts! (verify-operator-access) ERR-ADMIN-UNAUTHORIZED)
        (asserts! (validate-operator-address new-operator) ERR-INVALID-OPERATOR)
        (var-set protocol-operator new-operator)
        (ok true)
    )
)