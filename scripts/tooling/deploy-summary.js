// Prints a compact summary of `sf project deploy ... --json` output read from stdin.
let raw = "";
process.stdin
  .on("data", (d) => (raw += d))
  .on("end", () => {
    let json;
    try {
      json = JSON.parse(raw.slice(raw.indexOf("{")));
    } catch (e) {
      console.log(raw.slice(-4000));
      process.exit(1);
    }
    const r = json.result || json.data || {};
    console.log(
      `Status: ${r.status || json.name} | Deploy ID: ${r.id || "-"} | success: ${r.success}`
    );
    if (json.message && !r.status) console.log(json.message);
    const failures = (r.details && r.details.componentFailures) || [];
    []
      .concat(failures)
      .forEach((f) =>
        console.log(
          `COMPONENT ERROR ${f.componentType} ${f.fullName}: ${f.problem} (line ${f.lineNumber || "-"})`
        )
      );
    const tr = r.details && r.details.runTestResult;
    if (tr) {
      console.log(`Tests run: ${tr.numTestsRun}, failures: ${tr.numFailures}`);
      [].concat(tr.failures || []).forEach((f) =>
        console.log(
          `TEST FAIL ${f.name}.${f.methodName}: ${f.message}\n   ${String(
            f.stackTrace || ""
          )
            .split("\n")
            .join("\n   ")}`
        )
      );
      const warnings = [].concat(tr.codeCoverageWarnings || []);
      warnings.forEach((w) =>
        console.log(`COVERAGE WARNING ${w.name || ""}: ${w.message}`)
      );
      const cov = [].concat(tr.codeCoverage || []);
      let total = 0,
        uncovered = 0;
      cov.forEach((c) => {
        total += Number(c.numLocations);
        uncovered += Number(c.numLocationsNotCovered);
        const pct =
          c.numLocations > 0
            ? Math.round(
                (100 * (c.numLocations - c.numLocationsNotCovered)) /
                  c.numLocations
              )
            : 100;
        if (pct < 85) console.log(`  low coverage ${c.name}: ${pct}%`);
      });
      if (total)
        console.log(
          `Overall coverage: ${Math.round((100 * (total - uncovered)) / total)}%`
        );
    }
    process.exit(r.success ? 0 : 1);
  });
