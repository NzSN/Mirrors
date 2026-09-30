import Core.Tla.Source

/-! Reviewed import facts from TLA+ Tools 1.8.0 StandardModules. Local INSTANCE
dependencies are recorded but never re-exported. This catalog supplies no
invented operator declarations; the elaborator retains its reviewed facts.
-/
namespace Core.Tla

def standardCatalogIdentity : String := "mirrors-standard-modules/v2"
def standardCatalogBaseline : String := "TLA+ Tools 1.8.0"

/-- SHA-256 of the exact module bytes in the verified standalone 1.8.0 jar.
Extension modules without reviewed sources retain no content identity. -/
def standardModuleContentSha256? (name : String) : Option String :=
  List.lookup name [
    ("Naturals", "73f2a68412039aa86f37ad08f0d0fef50fa8327d0ad8806f515548c75e9d9d84"),
    ("Integers", "071da69e5eea383d361ef308ba12ecc931bf968fcea98175c3bca419bbd8cbf2"),
    ("Reals", "33cc699c0139b39fcee903d4dde255b64a0b430291630aa4825c6dd32b2f2fa2"),
    ("Sequences", "f613cffe14133769f0972b6f6e0139aaf0773004a51bac88ada382426e3eb7f4"),
    ("FiniteSets", "d94cb545256539bf782fc1914842dfe8c19c1d3d4e48b8327dd0c47b74922e1e"),
    ("Bags", "da36710bc779e289887d95c1f208214daf0c9a0ab0b0e2636086a8c17737e670"),
    ("TLC", "944ece590eec81ace059881c2a62064c06041efa81539a788cd40fa7d1da41ce"),
    ("TLCExt", "6c3e7e54cf1b8a4d2d1c7a5fd088f06452edce68ec28d8be99392cc0037a5399"),
    ("Toolbox", "9deac1facb0b71809714229dace116da75f80bf4c65b707ff40026f380c7804a"),
    ("Randomization", "998209fcb33bac3c9b4d6851dc5df5ca83d33722201cc5280b51a1f58fffaebf"),
    ("RealTime", "9052ccc8a150c93ae13a4d136da7b83dc68d1d8e9a0eee6f787db02b755f6682")]

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
