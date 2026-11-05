namespace Ffi

/-- Windows path attributes without following the final reparse point:
0 ordinary, 1 reparse point, 2 missing, 3 inspection failure.
Non-Windows hosts return 0 and use the runtime's lstat implementation. -/
@[extern "mirrors_path_reparse_status"]
opaque pathReparseStatus : @& String → BaseIO UInt32

end Ffi
