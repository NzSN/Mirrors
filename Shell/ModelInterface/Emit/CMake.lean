import Shell.ModelInterface.Emit.TypeScript
import Core.ModelInterface.Sha256

/-! Optional compiler-owned CMake consumer support. Freshness is a byte/digest
check over reviewed artifacts; it is not artifact authentication. -/
namespace Shell.ModelInterface.Emit.CMake
open Core.ModelInterface
open TypeScript

private def verifyScript : String := String.intercalate "\n" [
  "cmake_minimum_required(VERSION 3.24)",
  "function(mirrors_verify_model_interface input_root generated_root)",
  "  file(READ \"${generated_root}/MirrorInterface.inputs.json\" manifest)",
  "  string(JSON schema GET \"${manifest}\" schema)",
  "  if(NOT schema STREQUAL \"mirrors.model-interface-consumer/v1\")",
  "    message(FATAL_ERROR \"Unsupported Mirrors consumer manifest\")",
  "  endif()",
  "  set(allowed schema targetProfile semanticDigest compilerVersion compilerBinarySha256 inputs outputs resolveArguments generateArguments lockPath)",
  "  string(JSON member_count LENGTH \"${manifest}\")",
  "  list(LENGTH allowed expected_members)",
  "  if(NOT member_count EQUAL expected_members)",
  "    message(FATAL_ERROR \"Unexpected Mirrors manifest fields\")",
  "  endif()",
  "  math(EXPR last_member \"${member_count} - 1\")",
  "  foreach(index RANGE 0 ${last_member})",
  "    string(JSON member MEMBER \"${manifest}\" ${index})",
  "    if(NOT member IN_LIST allowed)",
  "      message(FATAL_ERROR \"Unknown Mirrors manifest field: ${member}\")",
  "    endif()",
  "  endforeach()",
  "  foreach(section IN ITEMS inputs outputs)",
  "    if(section STREQUAL inputs)",
  "      set(base \"${input_root}\")",
  "    else()",
  "      set(base \"${generated_root}\")",
  "    endif()",
  "    file(REAL_PATH \"${base}\" canonical_base)",
  "    string(JSON count LENGTH \"${manifest}\" ${section})",
  "    if(count LESS 1 OR count GREATER 8192)",
  "      message(FATAL_ERROR \"Invalid Mirrors artifact count\")",
  "    endif()",
  "    set(seen)",
  "    math(EXPR last \"${count} - 1\")",
  "    foreach(index RANGE 0 ${last})",
  "      string(JSON fields LENGTH \"${manifest}\" ${section} ${index})",
  "      if(NOT fields EQUAL 2)",
  "        message(FATAL_ERROR \"Unexpected Mirrors artifact fields\")",
  "      endif()",
  "      string(JSON relative GET \"${manifest}\" ${section} ${index} path)",
  "      string(JSON expected GET \"${manifest}\" ${section} ${index} sha256)",
  "      if(IS_ABSOLUTE \"${relative}\" OR relative MATCHES \"(^|[/\\\\\\\\])\\\\.\\\\.?([/\\\\\\\\]|$)\" OR relative MATCHES \"[:;\\\\\\\\]\" OR relative STREQUAL \"\")",
  "        message(FATAL_ERROR \"Unsafe Mirrors artifact path: ${relative}\")",
  "      endif()",
  "      string(TOLOWER \"${relative}\" alias)",
  "      if(alias IN_LIST seen)",
  "        message(FATAL_ERROR \"Duplicate Mirrors artifact path: ${relative}\")",
  "      endif()",
  "      list(APPEND seen \"${alias}\")",
  "      string(LENGTH \"${expected}\" hash_length)",
  "      if(NOT hash_length EQUAL 64 OR NOT expected MATCHES \"^[0-9a-f]+$\")",
  "        message(FATAL_ERROR \"Invalid Mirrors artifact hash\")",
  "      endif()",
  "      file(REAL_PATH \"${base}/${relative}\" actual_path)",
  "      cmake_path(IS_PREFIX canonical_base \"${actual_path}\" NORMALIZE contained)",
  "      if(NOT contained OR IS_SYMLINK \"${base}/${relative}\" OR NOT EXISTS \"${actual_path}\" OR IS_DIRECTORY \"${actual_path}\")",
  "        message(FATAL_ERROR \"Missing or escaping Mirrors artifact: ${relative}\")",
  "      endif()",
  "      file(SHA256 \"${actual_path}\" actual)",
  "      if(NOT actual STREQUAL expected)",
  "        message(FATAL_ERROR \"Mirrors interface is stale or modified: ${relative}\")",
  "      endif()",
  "    endforeach()",
  "  endforeach()",
  "  string(JSON lock_path GET \"${manifest}\" lockPath)",
  "  file(READ \"${input_root}/${lock_path}\" lock)",
  "  file(READ \"${generated_root}/.model-interface-generated.json\" ownership)",
  "  string(JSON expected_digest GET \"${manifest}\" semanticDigest)",
  "  string(JSON lock_digest GET \"${lock}\" semanticDigest)",
  "  string(JSON generated_digest GET \"${ownership}\" semanticDigest)",
  "  string(JSON target GET \"${manifest}\" targetProfile)",
  "  string(JSON generated_target GET \"${ownership}\" targetProfile)",
  "  if(NOT expected_digest STREQUAL lock_digest OR NOT expected_digest STREQUAL generated_digest OR NOT target STREQUAL generated_target)",
  "    message(FATAL_ERROR \"Mirrors semantic digest or target disagrees\")",
  "  endif()",
  "endfunction()",
  "if(DEFINED MIRRORS_INPUT_ROOT AND DEFINED MIRRORS_GENERATED_ROOT)",
  "  mirrors_verify_model_interface(\"${MIRRORS_INPUT_ROOT}\" \"${MIRRORS_GENERATED_ROOT}\")",
  "endif()"] ++ "\n"

private def helperScript : String := String.intercalate "\n" [
  "cmake_minimum_required(VERSION 3.24)",
  "include(\"${CMAKE_CURRENT_LIST_DIR}/MirrorVerify.cmake\")",
  "function(mirrors_add_model_interface name input_root)",
  "  if(NOT name MATCHES \"^[A-Za-z][A-Za-z0-9_]*$\")",
  "    message(FATAL_ERROR \"Invalid Mirrors CMake target name\")",
  "  endif()",
  "  cmake_parse_arguments(MI \"\" \"COMPILER\" \"\" ${ARGN})",
  "  if(MI_UNPARSED_ARGUMENTS OR MI_KEYWORDS_MISSING_VALUES)",
  "    message(FATAL_ERROR \"Invalid Mirrors CMake arguments\")",
  "  endif()",
  "  set(generated_root \"${CMAKE_CURRENT_FUNCTION_LIST_DIR}\")",
  "  mirrors_verify_model_interface(\"${input_root}\" \"${generated_root}\")",
  "  add_custom_target(${name}_verify",
  "    COMMAND \"${CMAKE_COMMAND}\" \"-DMIRRORS_INPUT_ROOT=${input_root}\" \"-DMIRRORS_GENERATED_ROOT=${generated_root}\" -P \"${generated_root}/MirrorVerify.cmake\"",
  "    VERBATIM)",
  "  add_library(${name} INTERFACE)",
  "  target_include_directories(${name} INTERFACE \"${generated_root}\")",
  "  target_compile_features(${name} INTERFACE cxx_std_23)",
  "  add_dependencies(${name} ${name}_verify)",
  "  if(MI_COMPILER)",
  "    file(READ \"${generated_root}/MirrorInterface.inputs.json\" manifest)",
  "    foreach(section IN ITEMS resolveArguments generateArguments)",
  "      string(JSON count LENGTH \"${manifest}\" ${section})",
  "      math(EXPR last \"${count} - 1\")",
  "      set(${section})",
  "      foreach(index RANGE 0 ${last})",
  "        string(JSON argument GET \"${manifest}\" ${section} ${index})",
  "        string(REPLACE \";\" \"\\\\;\" argument \"${argument}\")",
  "        list(APPEND ${section} \"${argument}\")",
  "      endforeach()",
  "    endforeach()",
  "    add_custom_target(${name}_regenerate",
  "      COMMAND \"${MI_COMPILER}\" ${resolveArguments}",
  "      COMMAND \"${MI_COMPILER}\" ${generateArguments}",
  "      WORKING_DIRECTORY \"${input_root}\"",
  "      VERBATIM)",
  "  endif()",
  "endfunction()"] ++ "\n"

def emit (lock : LockedModelInterface) (target : String) (binding : GeneratedTree)
    (inputs : List (String × String)) (lockPath : String)
    (resolveArguments generateArguments : List String) (compilerSha256 : String) : GeneratedTree :=
  let helper : GeneratedFile := { relativePath := "MirrorInterface.cmake", bytes := helperScript.toUTF8 }
  let verify : GeneratedFile := { relativePath := "MirrorVerify.cmake", bytes := verifyScript.toUTF8 }
  let paths := sortStrings (binding.files.map (·.relativePath) ++
    [helper.relativePath, verify.relativePath, "MirrorInterface.inputs.json"])
  let ownership := Codec.ModelInterfaceJson.canonicalFileBytes (Lean.Json.mkObj [
    ("files", .arr (paths.map Lean.Json.str).toArray),
    ("profileVersion", .num (if target == "mirrorcpp-v2" then 2 else 1)),
    ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str lock.semanticDigest), ("targetProfile", .str target)])
  let files := binding.files.map (fun file =>
    if file.relativePath == ".model-interface-generated.json" then { file with bytes := ownership }
    else file) ++ [helper, verify]
  let entry (path digest : String) := Lean.Json.mkObj [
    ("path", .str path), ("sha256", .str digest)]
  let strings (values : List String) := Lean.Json.arr (values.map Lean.Json.str).toArray
  let manifest := Codec.ModelInterfaceJson.canonicalFileBytes (Lean.Json.mkObj [
    ("schema", .str "mirrors.model-interface-consumer/v1"),
    ("targetProfile", .str target), ("semanticDigest", .str lock.semanticDigest),
    ("compilerVersion", .str lock.provenance.compilerVersion),
    ("compilerBinarySha256", .str compilerSha256),
    ("lockPath", .str lockPath),
    ("inputs", .arr ((inputs.map (fun (path, digest) => entry path digest)).toArray)),
    ("outputs", .arr ((files.map (fun file =>
      entry file.relativePath (Core.ModelInterface.Sha256.digestHex file.bytes))).toArray)),
    ("resolveArguments", strings resolveArguments), ("generateArguments", strings generateArguments)])
  { files := (files ++ [{ relativePath := "MirrorInterface.inputs.json", bytes := manifest }]).toArray.qsort
      (fun left right => compare left.relativePath right.relativePath == .lt) |>.toList }

end Shell.ModelInterface.Emit.CMake
