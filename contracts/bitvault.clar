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