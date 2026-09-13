/* Test-only SANY 1.8.0 semantic observation bridge.  It has no Mirrors input. */
import java.io.PrintStream;
import java.lang.reflect.Field;
import tla2sany.drivers.SANY;
import tla2sany.modanalyzer.SpecObj;
import tla2sany.semantic.ModuleNode;
import tla2sany.semantic.OpDeclNode;
import tla2sany.semantic.OpDefNode;
import tla2sany.semantic.InstanceNode;
import tla2sany.semantic.Subst;
import tla2sany.semantic.ExprOrOpArgNode;
import tla2sany.semantic.NumeralNode;
import tla2sany.semantic.StringNode;
import tla2sany.semantic.OpApplNode;

public final class SanyBridge {
  private static String quote(String value) {
    StringBuilder result = new StringBuilder("\"");
    for (int i = 0; i < value.length(); i++) {
      char c = value.charAt(i);
      if (c == '\\' || c == '"') result.append('\\').append(c);
      else if (c < 32) result.append(String.format("\\u%04x", (int)c));
      else result.append(c);
    }
    return result.append('"').toString();
  }

  private static void declarations(StringBuilder out, ModuleNode module) {
    boolean first = true;
    for (OpDeclNode variable : module.getVariableDecls()) {
      if (!first) out.append(','); first = false;
      out.append("{\"kind\":\"variable\",\"name\":").append(quote(variable.getName().toString()))
        .append(",\"declaredIn\":").append(quote(variable.getOriginallyDefinedInModuleNode().getName().toString()))
        .append(",\"arity\":").append(variable.getNumberOfArgs()).append("}");
    }
    for (OpDeclNode constant : module.getConstantDecls()) {
      if (!first) out.append(','); first = false;
      out.append("{\"kind\":\"constant\",\"name\":").append(quote(constant.getName().toString()))
        .append(",\"declaredIn\":").append(quote(constant.getOriginallyDefinedInModuleNode().getName().toString()))
        .append(",\"arity\":").append(constant.getNumberOfArgs()).append("}");
    }
    for (OpDefNode operator : module.getOpDefs()) {
      OpDefNode original = operator;
      for (int hops = 0; hops < 64; hops++) {
        OpDefNode next = original.getSource();
        if (next == null || next == original) break;
        original = next;
        if (hops == 63) throw new IllegalStateException("operator source chain exceeds bound");
      }
      if (!first) out.append(','); first = false;
      out.append("{\"kind\":\"operator\",\"name\":").append(quote(operator.getName().toString()))
        .append(",\"declaredIn\":").append(quote(original.getOriginallyDefinedInModuleNode().getName().toString()))
        .append(",\"arity\":").append(operator.getNumberOfArgs())
        .append(",\"local\":").append(operator.isLocal()).append(",\"level\":").append(operator.getLevel()).append("}");
    }
  }

  private static void atom(StringBuilder out, ExprOrOpArgNode value) {
    if (value instanceof NumeralNode) out.append("{\"kind\":\"integer\",\"value\":").append((((NumeralNode)value).useVal() ? Integer.toString(((NumeralNode)value).val()) : ((NumeralNode)value).bigVal().toString())).append("}");
    else if (value instanceof StringNode) out.append("{\"kind\":\"string\",\"value\":").append(quote(((StringNode)value).getRep().toString())).append("}");
    else if (value instanceof OpApplNode && ((OpApplNode)value).getArgs().length == 0) {
      String name = ((OpApplNode)value).getOperator().getName().toString();
      if (name.equals("TRUE") || name.equals("FALSE")) out.append("{\"kind\":\"boolean\",\"value\":").append(name.equals("TRUE")).append("}");
      else out.append("{\"kind\":\"name\",\"value\":").append(quote(name)).append("}");
    } else out.append("null");
  }

  private static void instances(StringBuilder out, ModuleNode module) throws Exception {
    Field field = InstanceNode.class.getDeclaredField("substs"); field.setAccessible(true);
    boolean first = true;
    for (InstanceNode instance : module.getInstances()) {
      if (!instance.getLocation().source().equals(module.getName().toString())) continue;
      if (!first) out.append(','); first = false;
      out.append("{\"owner\":").append(quote(module.getName().toString())).append(",\"name\":");
      if (instance.getName() == null || instance.getName().toString().isEmpty()) out.append("null"); else out.append(quote(instance.getName().toString()));
      out.append(",\"module\":").append(quote(instance.getModule().getName().toString())).append(",\"local\":").append(instance.getLocal()).append(",\"line\":").append(instance.getLocation().beginLine()).append(",\"substitutions\":[");
      boolean firstSub = true;
      for (Subst subst : (Subst[])field.get(instance)) { if (!firstSub) out.append(','); firstSub=false;
        out.append("{\"formal\":").append(quote(subst.getOp().getName().toString())).append(",\"actual\":"); atom(out, subst.getExpr()); out.append(",\"implicit\":").append(subst.isImplicit()).append("}"); }
      out.append("]}");
    }
  }

  private static void dependencies(StringBuilder out, ModuleNode module) {
    boolean first = true;
    for (ModuleNode dependency : module.getExtendedModuleSet(false)) {
      if (!first) out.append(','); first = false;
      out.append("{\"owner\":").append(quote(module.getName().toString()))
        .append(",\"dependency\":").append(quote(dependency.getName().toString()))
        .append(",\"kind\":\"extends\",\"local\":false}");
    }
    for (InstanceNode inst : module.getInstances()) {
      // Imported instance nodes retain their source location; emit only sites
      // declared by this owner, not duplicates introduced by EXTENDS.
      if (!inst.getLocation().source().equals(module.getName().toString())) continue;
      if (!first) out.append(','); first = false;
      String kind = inst.getName() == null || inst.getName().toString().isEmpty() ? "unnamedInstance" : "namedInstance";
      out.append("{\"owner\":").append(quote(module.getName().toString()))
        .append(",\"dependency\":").append(quote(inst.getModule().getName().toString()))
        .append(",\"kind\":").append(quote(kind)).append(",\"local\":").append(inst.getLocal()).append('}');
    }
  }

  public static void main(String[] args) {
    if (args.length != 1) { System.err.println("usage: SanyBridge MODULE.tla"); System.exit(64); }
    try {
      SpecObj spec = new SpecObj(args[0]);
      int exit = SANY.frontEndMain(spec, args[0], new PrintStream(System.err));
      boolean parseOk = spec.getParseErrors().isSuccess();
      boolean semanticOk = spec.getSemanticErrors().isSuccess();
      ModuleNode root = spec.getRootModule();
      boolean ok = exit == 0 && parseOk && semanticOk && root != null;
      StringBuilder out = new StringBuilder();
      out.append("{\"schema\":\"mirrors.sany-bridge/v1\",\"exitCode\":").append(exit)
        .append(",\"ok\":").append(ok).append(",\"parseOk\":").append(parseOk)
        .append(",\"semanticOk\":").append(semanticOk)
        .append(",\"errorLevel\":").append(spec.getErrorLevel())
        .append(",\"root\":").append(root == null ? "null" : quote(root.getName().toString()))
        .append(",\"modules\":[");
      if (ok) {
        boolean first = true;
        for (ModuleNode module : spec.getExternalModuleTable().getModuleNodes()) {
          if (!first) out.append(','); first = false;
          out.append("{\"name\":").append(quote(module.getName().toString()))
            .append(",\"standard\":").append(module.isStandard())
            .append(",\"declarations\":["); declarations(out, module);
          out.append("],\"instances\":["); instances(out, module);
          out.append("],\"dependencies\":["); dependencies(out, module);
          out.append("]}");
        }
      }
      out.append("]}");
      System.out.println(out);
    } catch (Throwable error) {
      System.err.println("SanyBridge: " + error);
      System.out.println("{\"schema\":\"mirrors.sany-bridge/v1\",\"bridgeError\":true}");
      System.exit(70);
    }
  }
}
