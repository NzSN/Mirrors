import Core.Tla.Source

/-! Reviewed import facts from TLA+ Tools 1.8.0 StandardModules. Local INSTANCE
dependencies are recorded but never re-exported. This catalog supplies no
invented operator declarations; the elaborator retains its reviewed facts.
-/
namespace Core.Tla

def standardCatalogIdentity : String := "mirrors-standard-modules/v2"
def standardCatalogBaseline : String := "TLA+ Tools 1.8.0"

structure StandardDependency where
  owner : ModuleName
  dependency : ModuleName
  localOnly : Bool := false
  deriving Repr, BEq

def standardDependencies : Array StandardDependency := #[
  { owner := ⟨"Integers"⟩, dependency := ⟨"Naturals"⟩ },
  { owner := ⟨"Reals"⟩, dependency := ⟨"Integers"⟩ },
  { owner := ⟨"Bags"⟩, dependency := ⟨"TLC"⟩ },
  { owner := ⟨"RealTime"⟩, dependency := ⟨"Reals"⟩ },
  { owner := ⟨"Sequences"⟩, dependency := ⟨"Naturals"⟩, localOnly := true },
  { owner := ⟨"FiniteSets"⟩, dependency := ⟨"Naturals"⟩, localOnly := true },
  { owner := ⟨"FiniteSets"⟩, dependency := ⟨"Sequences"⟩, localOnly := true },
  { owner := ⟨"Bags"⟩, dependency := ⟨"Naturals"⟩, localOnly := true },
  { owner := ⟨"TLC"⟩, dependency := ⟨"Naturals"⟩, localOnly := true },
  { owner := ⟨"TLC"⟩, dependency := ⟨"Sequences"⟩, localOnly := true },
  { owner := ⟨"TLC"⟩, dependency := ⟨"FiniteSets"⟩, localOnly := true },
  { owner := ⟨"TLCExt"⟩, dependency := ⟨"TLC"⟩, localOnly := true },
  { owner := ⟨"TLCExt"⟩, dependency := ⟨"Integers"⟩, localOnly := true },
  { owner := ⟨"Toolbox"⟩, dependency := ⟨"Naturals"⟩, localOnly := true },
  { owner := ⟨"Toolbox"⟩, dependency := ⟨"FiniteSets"⟩, localOnly := true },
  { owner := ⟨"Toolbox"⟩, dependency := ⟨"TLC"⟩, localOnly := true },
  { owner := ⟨"Randomization"⟩, dependency := ⟨"Naturals"⟩, localOnly := true },
  { owner := ⟨"Randomization"⟩, dependency := ⟨"FiniteSets"⟩, localOnly := true }]

private def exportClosure : Nat → ModuleName → Array ModuleName
  | 0, name => #[name]
  | fuel + 1, name =>
      standardDependencies.foldl (fun names edge =>
        if edge.owner == name && !edge.localOnly then
          (exportClosure fuel edge.dependency).foldl (fun acc dependency =>
            if acc.contains dependency then acc else acc.push dependency) names
        else names) #[name]

/-- Public module visibility, bounded by the size of the reviewed acyclic graph.
Unknown modules expose only themselves, and acquire no declaration facts. -/
def standardExportClosure (name : ModuleName) : Array ModuleName :=
  exportClosure (standardDependencies.size + 1) name

def standardExports (owner declarationModule : ModuleName) : Bool :=
  (standardExportClosure owner).contains declarationModule

end Core.Tla
