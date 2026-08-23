// Resolve ".js" specifiers to their ".ts" sources so the unmodified
// MirrorECMA TypeScript sources run directly under Node type-stripping.
export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context);
  } catch (err) {
    if (specifier.endsWith(".js") && !specifier.startsWith("node:")) {
      try {
        return await nextResolve(specifier.slice(0, -3) + ".ts", context);
      } catch { /* fall through */ }
    }
    throw err;
  }
}
