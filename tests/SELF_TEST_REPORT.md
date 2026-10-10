---
doc_id: "report-019"
title: "Engineering self-test report"
category: "report"
role: "[Delta]"
status: "published"
date: "2026-09-13"
author: "未标注（2026-09-15 治理补录）"
tags: ["self", "test", "report"]
related: []
---

# Engineering self-test report

`ENGINEERING TEST ONLY` — synthetic fixture output is not a paper result.

Executed on 2026-09-12:

```text
python -m unittest discover -s revision/tests -v
Ran 13 tests in 0.200s
OK
```

PowerShell CLI wrapper also completed in a new empty output directory with `-PythonExe python -BaselineVariant default -BaselineConfigId frozen -ProtocolId frozen_protocol_v1 -StateList revision/tests/temp/states.txt -ExpectedHopS 8 -Bootstrap 100 -Permutations 100 -NoFigures` using `revision/tests/temp/predictions.csv` and `revision/tests/temp/expected_windows.csv`. Metadata recorded the requested hop and failure episode definition; the all-success fixture produced a header-only `failure_episodes.csv`.

Observed synthetic checks:

```text
baseline subject_macro_mae=3.5, window_pooled_mae=3.2, coverage=1.0
candidate subject_macro_mae=0.0, window_pooled_mae=0.0, coverage=1.0
candidate paired mean_subject_mae_difference=-3.5, exact signflip_p=0.5, holm_p_by_dataset=0.5
```

Generated files are under `revision/tests/temp/cli_output_20260912/`; they are excluded from any manuscript result path by design.


2026-09-30T12:49:34+08:00：统一unittest入口17/17通过（13既有+4四臂数学/列序测试）。ENGINEERING TEST ONLY。另对真实保存差值作独立精确枚举，12个p完全一致；不能把工程通过当作科学采用许可。
