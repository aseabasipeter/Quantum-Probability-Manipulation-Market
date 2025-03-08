;; Multiverse Branch Speculation Contract
;; Allows users to speculate on branch creation in the multiverse

(define-map branch-points
  { id: uint }
  {
    description: (string-utf8 128),
    creation-probability: uint,
    decision-point: uint,
    is-verified: bool,
    did-branch: bool
  }
)

(define-map speculations
  { id: uint }
  {
    branch-id: uint,
    speculator: principal,
    amount: uint,
    speculation-type: (string-ascii 10), ;; "branch" or "no-branch"
    is-claimed: bool
  }
)

(define-data-var next-branch-id uint u0)
(define-data-var next-speculation-id uint u0)

;; Register a potential branch point in the multiverse
(define-public (register-branch-point (description (string-utf8 128)) (creation-probability uint) (decision-point uint))
  (let
    ((branch-id (var-get next-branch-id)))
    (var-set next-branch-id (+ branch-id u1))
    (ok (map-set branch-points
      { id: branch-id }
      {
        description: description,
        creation-probability: creation-probability,
        decision-point: decision-point,
        is-verified: false,
        did-branch: false
      }
    ))
  )
)

;; Place a speculation on whether a branch will form
(define-public (place-speculation (branch-id uint) (amount uint) (speculation-type (string-ascii 10)))
  (match (map-get? branch-points { id: branch-id })
    branch-point
      (begin
        (asserts! (not (get is-verified branch-point)) (err u403))
        (asserts! (or (is-eq speculation-type "branch") (is-eq speculation-type "no-branch")) (err u400))

        (let
          ((speculation-id (var-get next-speculation-id)))
          (var-set next-speculation-id (+ speculation-id u1))
          (ok (map-set speculations
            { id: speculation-id }
            {
              branch-id: branch-id,
              speculator: tx-sender,
              amount: amount,
              speculation-type: speculation-type,
              is-claimed: false
            }
          ))
        )
      )
    (err u404)
  )
)

;; Verify a branch point (determine if branching occurred)
(define-public (verify-branch-point (branch-id uint) (did-branch bool))
  (match (map-get? branch-points { id: branch-id })
    branch-point
      (begin
        (asserts! (not (get is-verified branch-point)) (err u403))
        (ok (map-set branch-points
          { id: branch-id }
          (merge branch-point {
            is-verified: true,
            did-branch: did-branch
          })
        ))
      )
    (err u404)
  )
)

;; Claim rewards for correct speculation
(define-public (claim-speculation-reward (speculation-id uint))
  (match (map-get? speculations { id: speculation-id })
    speculation
      (begin
        (asserts! (is-eq tx-sender (get speculator speculation)) (err u403))
        (asserts! (not (get is-claimed speculation)) (err u403))

        (match (map-get? branch-points { id: (get branch-id speculation) })
          branch-point
            (begin
              (asserts! (get is-verified branch-point) (err u403))

              (let
                ((is-correct (or
                               (and (is-eq (get speculation-type speculation) "branch") (get did-branch branch-point))
                               (and (is-eq (get speculation-type speculation) "no-branch") (not (get did-branch branch-point)))
                             )))

                ;; Mark speculation as claimed
                (map-set speculations
                  { id: speculation-id }
                  (merge speculation { is-claimed: true })
                )

                ;; Return reward if correct, 0 if incorrect
                (if is-correct
                  (ok (calculate-reward speculation branch-point))
                  (ok u0))
              )
            )
          (err u404))
      )
    (err u404)
  )
)

;; Calculate reward based on probability and amount
(define-private (calculate-reward (speculation { branch-id: uint, speculator: principal, amount: uint, speculation-type: (string-ascii 10), is-claimed: bool })
                                 (branch-point { description: (string-utf8 128), creation-probability: uint, decision-point: uint, is-verified: bool, did-branch: bool }))
  (let
    ((base-amount (get amount speculation))
     (probability (if (is-eq (get speculation-type speculation) "branch")
                    (get creation-probability branch-point)
                    (- u10000 (get creation-probability branch-point)))))

    ;; Reward is inversely proportional to the probability
    (if (> probability u0)
      (/ (* base-amount u10000) probability)
      u0)
  )
)

;; Get branch point details
(define-read-only (get-branch-point (branch-id uint))
  (map-get? branch-points { id: branch-id })
)

;; Get speculation details
(define-read-only (get-speculation (speculation-id uint))
  (map-get? speculations { id: speculation-id })
)

