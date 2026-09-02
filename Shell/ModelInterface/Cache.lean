import Core.ModelInterface.Sha256
import Core.ModelInterface.Types
import Std.Sync.Mutex

/-!
# Bounded process-local model-interface descriptor cache

The cache is content-verified and scoped by authorization realm, principal,
tenant, and deterministic resolution fingerprint. It stores canonical semantic
descriptor bytes only; contracts, sources, diagnostics, and generated code are
never cached here.
-/

namespace Shell.ModelInterface.Cache

def descriptorDigestDomain : String :=
  Core.ModelInterface.descriptorDigestDomainV1

structure ScopedResolutionKey where
  securityRealm : String
  principalId : Option String := none
  tenantId : Option String
  fingerprint : String
  deriving Repr, BEq

structure Entry where
  key : ScopedResolutionKey
  semanticDigest : String
  bytes : ByteArray
  lastUsed : Nat

private structure State where
  clock : Nat := 0
  entries : List Entry := []

structure DescriptorCache where
  mu : Std.Mutex State
  maxEntries : Nat
  maxBytes : Nat
  maxEntriesPerScope : Nat
  maxBytesPerScope : Nat

def semanticDigest (canonicalBytes : ByteArray) : String :=
  "sha256:" ++ Core.ModelInterface.Sha256.digestDomainHex
    descriptorDigestDomain canonicalBytes

private def totalBytes (entries : List Entry) : Nat :=
  entries.foldl (fun n entry => n + entry.bytes.size) 0

private def newestFirst (entries : List Entry) : List Entry :=
  entries.toArray.qsort (fun a b => a.lastUsed > b.lastUsed) |>.toList

private def bounded (maxEntries maxBytes : Nat) (entries : List Entry) : List Entry :=
  let rec go (remaining : List Entry) (count bytes : Nat) (out : List Entry) :=
    match remaining with
    | [] => out.reverse
    | entry :: rest =>
        if count < maxEntries && bytes + entry.bytes.size ≤ maxBytes then
          go rest (count + 1) (bytes + entry.bytes.size) (entry :: out)
        else
          go rest count bytes out
  go (newestFirst entries) 0 0 []

def new (maxEntries : Nat := 128) (maxBytes : Nat := 16 * 1024 * 1024)
    (maxEntriesPerScope : Nat := 32)
    (maxBytesPerScope : Nat := 4 * 1024 * 1024) :
    BaseIO DescriptorCache := do
  return {
    mu := ← Std.Mutex.new {}
    maxEntries := max 1 maxEntries
    maxBytes := max 1 maxBytes
    maxEntriesPerScope := max 1 (min maxEntries maxEntriesPerScope)
    maxBytesPerScope := max 1 (min maxBytes maxBytesPerScope)
  }

private def sameScope (left right : ScopedResolutionKey) : Bool :=
  left.securityRealm == right.securityRealm && left.principalId == right.principalId &&
    left.tenantId == right.tenantId

/-- Content-verified lookup. Corrupt entries are removed and reported as a
miss; they are never returned to a client. -/
def lookup (cache : DescriptorCache) (key : ScopedResolutionKey) : IO (Option Entry) :=
  cache.mu.atomically do
    let state ← get
    match state.entries.find? (fun entry => entry.key == key) with
    | none => return none
    | some entry =>
        if semanticDigest entry.bytes != entry.semanticDigest then
          set { state with entries := state.entries.filter (fun e => !(e.key == key)) }
          return none
        else
          let clock := state.clock + 1
          let touched := { entry with lastUsed := clock }
          let entries := touched :: state.entries.filter (fun e => !(e.key == key))
          set ({ clock := clock, entries := entries } : State)
          return some touched

/-- Atomically publish canonical descriptor bytes. A caller-provided digest
must match the bytes, and an existing digest may never name different bytes. -/
def put (cache : DescriptorCache) (key : ScopedResolutionKey)
    (claimedDigest : String) (bytes : ByteArray) : IO (Except String Unit) :=
  cache.mu.atomically do
    let state ← get
    let actual := semanticDigest bytes
    if claimedDigest != actual then
      return .error "descriptor digest does not match canonical bytes"
    match state.entries.find? (fun entry =>
        entry.semanticDigest == claimedDigest && entry.bytes != bytes) with
    | some _ => return .error "semantic digest already names different bytes"
    | none =>
        let clock := state.clock + 1
        let entry : Entry := { key, semanticDigest := actual, bytes, lastUsed := clock }
        let entries := entry :: state.entries.filter (fun e => !(e.key == key))
        let scopeEntries := entries.filter (fun e => sameScope e.key key)
        let otherScopes := entries.filter (fun e => !sameScope e.key key)
        let entries := bounded cache.maxEntriesPerScope cache.maxBytesPerScope scopeEntries ++
          otherScopes
        let entries := bounded cache.maxEntries cache.maxBytes entries
        set ({ clock := clock, entries := entries } : State)
        return .ok ()

def entryCount (cache : DescriptorCache) : IO Nat :=
  cache.mu.atomically do
    let state ← get
    return state.entries.length

def byteCount (cache : DescriptorCache) : IO Nat :=
  cache.mu.atomically do
    let state ← get
    return totalBytes state.entries

end Shell.ModelInterface.Cache
