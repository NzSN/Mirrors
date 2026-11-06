def main : IO Unit := do
  IO.println s!"native Rust root: {← IO.getEnv "RUST_REPO"}"
  for executable in #["bash", "C:/Program Files/Git/bin/bash.exe"] do
    let out ← IO.Process.output {cmd := executable, args := #["-c", "printf '%s\\n' \"$OSTYPE\" \"$RUST_REPO\"\ncommand -v bash\ncommand -v cargo\nif test -f \"$(cygpath -u \"$RUST_REPO\")/Cargo.toml\"; then printf '%s\\n' 'Rust SDK present'; fi"]}
    IO.println s!"selected {executable}: exit={out.exitCode}"
    IO.print out.stdout
    IO.eprint out.stderr
