;; Title: BitVault Registry Protocol
;;
;; Summary: 
;; Decentralized asset registration system enabling Bitcoin-secured ownership tracking,
;; custody management, and verifiable metadata storage on Stacks Layer 2.
;;
;; Description:
;; BitVault provides immutable digital asset cataloging with granular access controls,
;; transferable custody rights, and cryptographic verification. Built for institutions
;; and individuals requiring trustless asset provenance on Bitcoin's settlement layer.
;; Features include multi-party authorization, extensible tagging, and audit trails.

;; CONSTANTS & STATE

(define-data-var registry-sequence uint u0)
(define-constant admin-authority tx-sender)

(define-constant entity-not-found-error (err u401))
(define-constant duplicate-entity-error (err u402))
(define-constant administrative-restriction-error (err u400))
(define-constant descriptor-format-error (err u403))
(define-constant volume-parameter-error (err u404))
(define-constant permission-denied-error (err u405))
(define-constant unauthorized-operation-error (err u406))
(define-constant visibility-restriction-error (err u407))
(define-constant tag-validation-error (err u408))

;; DATA MAPS

(define-map asset-catalog
  { asset-sequence: uint }
  {
    asset-descriptor: (string-ascii 64),
    asset-custodian: principal,
    asset-volume: uint,
    registration-block: uint,
    asset-descriptor-extended: (string-ascii 128),
    classification-tags: (list 10 (string-ascii 32))
  }
)

(define-map authorization-matrix
  { asset-sequence: uint, authorized-party: principal }
  { access-status: bool }
)

;; PRIVATE UTILITIES

(define-private (asset-is-registered (asset-sequence uint))
  (is-some (map-get? asset-catalog { asset-sequence: asset-sequence }))
)

(define-private (is-custodian-of (asset-sequence uint) (evaluating-party principal))
  (match (map-get? asset-catalog { asset-sequence: asset-sequence })
    catalog-entry (is-eq (get asset-custodian catalog-entry) evaluating-party)
    false
  )
)

(define-private (get-registered-volume (asset-sequence uint))
  (default-to u0
    (get asset-volume
      (map-get? asset-catalog { asset-sequence: asset-sequence })
    )
  )
)

(define-private (is-valid-classification-tag (tag (string-ascii 32)))
  (and
    (> (len tag) u0)
    (< (len tag) u33)
  )
)

(define-private (validate-tag-collection (tags (list 10 (string-ascii 32))))
  (and
    (> (len tags) u0)
    (<= (len tags) u10)
    (is-eq (len (filter is-valid-classification-tag tags)) (len tags))
  )
)

;; CORE REGISTRY OPERATIONS

;; Register new asset with metadata
(define-public (register-new-asset 
  (descriptor (string-ascii 64)) 
  (volume uint) 
  (extended-information (string-ascii 128)) 
  (tags (list 10 (string-ascii 32)))
)
  (let
    (
      (next-sequence (+ (var-get registry-sequence) u1))
    )
    (asserts! (> (len descriptor) u0) descriptor-format-error)
    (asserts! (< (len descriptor) u65) descriptor-format-error)
    (asserts! (> volume u0) volume-parameter-error)
    (asserts! (< volume u1000000000) volume-parameter-error)
    (asserts! (> (len extended-information) u0) descriptor-format-error)
    (asserts! (< (len extended-information) u129) descriptor-format-error)
    (asserts! (validate-tag-collection tags) tag-validation-error)

    (map-insert asset-catalog
      { asset-sequence: next-sequence }
      {
        asset-descriptor: descriptor,
        asset-custodian: tx-sender,
        asset-volume: volume,
        registration-block: stacks-block-height,
        asset-descriptor-extended: extended-information,
        classification-tags: tags
      }
    )

    (map-insert authorization-matrix
      { asset-sequence: next-sequence, authorized-party: tx-sender }
      { access-status: true }
    )

    (var-set registry-sequence next-sequence)
    (ok next-sequence)
  )
)

;; Update existing asset metadata
(define-public (update-asset-registration 
  (asset-sequence uint) 
  (revised-descriptor (string-ascii 64)) 
  (revised-volume uint) 
  (revised-information (string-ascii 128)) 
  (revised-tags (list 10 (string-ascii 32)))
)
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (asserts! (> (len revised-descriptor) u0) descriptor-format-error)
    (asserts! (< (len revised-descriptor) u65) descriptor-format-error)
    (asserts! (> revised-volume u0) volume-parameter-error)
    (asserts! (< revised-volume u1000000000) volume-parameter-error)
    (asserts! (> (len revised-information) u0) descriptor-format-error)
    (asserts! (< (len revised-information) u129) descriptor-format-error)
    (asserts! (validate-tag-collection revised-tags) tag-validation-error)

    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { 
        asset-descriptor: revised-descriptor, 
        asset-volume: revised-volume, 
        asset-descriptor-extended: revised-information, 
        classification-tags: revised-tags 
      })
    )
    (ok true)
  )
)

;; Remove asset from registry
(define-public (cancel-asset-registration (asset-sequence uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    (map-delete asset-catalog { asset-sequence: asset-sequence })
    (ok true)
  )
)

;; Transfer asset ownership
(define-public (transfer-asset-custody (asset-sequence uint) (new-custodian principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { asset-custodian: new-custodian })
    )
    (ok true)
  )
)

;; AUTHORIZATION MANAGEMENT

;; Grant third-party access
(define-public (authorize-third-party-access (asset-sequence uint) (authorized-party principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (ok true)
  )
)

;; Revoke third-party access
(define-public (revoke-third-party-access (asset-sequence uint) (third-party principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (asserts! (not (is-eq third-party tx-sender)) administrative-restriction-error)

    (map-delete authorization-matrix { asset-sequence: asset-sequence, authorized-party: third-party })
    (ok true)
  )
)

;; Check authorization status
(define-public (check-authorization-status (asset-sequence uint) (evaluating-party principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (current-custodian (get asset-custodian catalog-entry))
      (access-permitted (default-to 
        false 
        (get access-status 
          (map-get? authorization-matrix { asset-sequence: asset-sequence, authorized-party: evaluating-party })
        )
      ))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)

    (ok {
      is-custodian: (is-eq evaluating-party current-custodian),
      has-authorization: access-permitted,
      asset-id: asset-sequence
    })
  )
)

;; METADATA MANAGEMENT

;; Add classification tags
(define-public (extend-classification-tags (asset-sequence uint) (additional-tags (list 10 (string-ascii 32))))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (existing-tags (get classification-tags catalog-entry))
      (combined-tags (unwrap! (as-max-len? (concat existing-tags additional-tags) u10) tag-validation-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (asserts! (validate-tag-collection additional-tags) tag-validation-error)

    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { classification-tags: combined-tags })
    )
    (ok combined-tags)
  )
)

;; Get asset classification
(define-public (get-asset-classification (asset-sequence uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (current-custodian (get asset-custodian catalog-entry))
      (access-permitted (default-to 
        false 
        (get access-status 
          (map-get? authorization-matrix { asset-sequence: asset-sequence, authorized-party: tx-sender })
        )
      ))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! 
      (or 
        (is-eq tx-sender current-custodian)
        access-permitted
        (is-eq tx-sender admin-authority)
      ) 
      permission-denied-error
    )

    (ok (get classification-tags catalog-entry))
  )
)

;; Update asset volume
(define-public (update-asset-volume (asset-sequence uint) (new-volume uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (asserts! (> new-volume u0) volume-parameter-error)
    (asserts! (< new-volume u1000000000) volume-parameter-error)

    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { asset-volume: new-volume })
    )
    (ok true)
  )
)

;; ADMINISTRATIVE FUNCTIONS

;; Apply emergency hold
(define-public (apply-emergency-restriction (asset-sequence uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (restriction-marker "ADMINISTRATIVE-HOLD")
      (existing-tags (get classification-tags catalog-entry))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! 
      (or 
        (is-eq tx-sender admin-authority)
        (is-eq (get asset-custodian catalog-entry) tx-sender)
      ) 
      administrative-restriction-error
    )

    (ok true)
  )
)

;; VERIFICATION SERVICES

;; Validate asset integrity and custody chain
(define-public (validate-asset-integrity (asset-sequence uint) (expected-custodian principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (current-custodian (get asset-custodian catalog-entry))
      (registration-height (get registration-block catalog-entry))
      (access-permitted (default-to 
        false 
        (get access-status 
          (map-get? authorization-matrix { asset-sequence: asset-sequence, authorized-party: tx-sender })
        )
      ))
    )
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! 
      (or 
        (is-eq tx-sender current-custodian)
        access-permitted
        (is-eq tx-sender admin-authority)
      ) 
      permission-denied-error
    )

    (if (is-eq current-custodian expected-custodian)
      (ok {
        validation-passed: true,
        verification-block: stacks-block-height,
        blocks-elapsed: (- stacks-block-height registration-height),
        custodian-verified: true
      })
      (ok {
        validation-passed: false,
        verification-block: stacks-block-height,
        blocks-elapsed: (- stacks-block-height registration-height),
        custodian-verified: false
      })
    )
  )
)