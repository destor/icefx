#!/usr/bin/env bash
# Build the Mudlet package. Output: dist/IcesusEffects.mpackage
#
# The scripts live in src/ as plain Lua so they can be edited and
# unit-tested directly; this wraps them, plus the `icefx` alias, into
# the package XML Mudlet expects, and zips that with config.lua.
# Mudlet runs the scripts top to bottom, so SOURCES order is load order.
#
# Usage: ./build/build.sh
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR=dist
OUT="$OUT_DIR/IcesusEffects.mpackage"
mkdir -p "$OUT_DIR"
rm -f "$OUT"

python3 - "$OUT" <<'PY'
import sys, zipfile
out = sys.argv[1]
SOURCES = ["builtins", "data", "ui", "controller"]

scripts = []
for name in SOURCES:
    path = f"src/{name}.lua"
    lua = open(path, encoding="utf-8").read()
    if "]]>" in lua:
        sys.exit(f"{path} contains ']]>', which would end the CDATA block")
    scripts.append(f"""   <Script isActive="yes" isFolder="no">
    <name>icesusfx.{name}</name>
    <packageName></packageName>
    <script><![CDATA[{lua}]]></script>
    <eventHandlerList />
   </Script>""")
scripts = "\n".join(scripts)

xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MudletPackage>
<MudletPackage version="1.001">
 <TriggerPackage></TriggerPackage>
 <TimerPackage></TimerPackage>
 <AliasPackage>
  <AliasGroup isActive="yes" isFolder="yes">
   <name>IcesusEffects</name>
   <script></script>
   <command></command>
   <packageName>IcesusEffects</packageName>
   <regex></regex>
   <Alias isActive="yes" isFolder="no">
    <name>icefx</name>
    <script>if icesusfx and icesusfx.command then
  icesusfx.command(matches[2] or "")
else
  cecho("\\n&lt;red&gt;icefx: Icesus Effects package not loaded.&lt;reset&gt;\\n")
end</script>
    <command></command>
    <packageName></packageName>
    <regex>^icefx(?:\\s+(.*))?$</regex>
   </Alias>
  </AliasGroup>
 </AliasPackage>
 <ActionPackage></ActionPackage>
 <ScriptPackage>
  <ScriptGroup isActive="yes" isFolder="yes">
   <name>IcesusEffects</name>
   <packageName>IcesusEffects</packageName>
   <script></script>
   <eventHandlerList />
{scripts}
  </ScriptGroup>
 </ScriptPackage>
 <KeyPackage></KeyPackage>
 <HelpPackage></HelpPackage>
</MudletPackage>
"""

import xml.etree.ElementTree as ET
ET.fromstring(xml.split("\n", 2)[2])  # fail the build on malformed XML

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("IcesusEffects.xml", xml)
    z.write("package/config.lua", "config.lua")
PY

echo "Built $OUT"
unzip -l "$OUT"
