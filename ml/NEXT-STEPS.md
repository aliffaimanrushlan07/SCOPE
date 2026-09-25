# Raising classifier rigour — what was done, and what is left

Supervisor feedback: *precision is not sufficient; add further training
techniques, sourced from reliable repositories.*

This file exists because the obvious reading of that feedback — "the precision
number is low" — was not what the evidence said. v1's test precision was
**0.977**. What was thin was the **method and the evidence behind that number**,
and one step of it was methodologically wrong.

Sections 1–4 are now **done** and produced `vit-scope-v2`. Sections 5 and 6 are
still open. The section numbering is fixed: `select_threshold.py`,
`score_split.py` and the notebook all cite these sections by number.

---

## Where things stand

| | Technique | State |
|---|---|---|
| §1 | Threshold selected on validation, reported on test | ✅ done — 0.63 |
| §2 | DeiT-style augmentation | ✅ done, except Mixup/CutMix |
| §3 | Precision/recall/PR-AUC metrics, PR-AUC early stopping, label smoothing | ✅ done |
| §4 | Seed study, mean ± SD | ✅ done — 3 seeds |
| §5 | Calibration (temperature scaling) | ❌ outstanding |
| §6 | TTA, hard negatives, ≥2-of-3 rule | ◐ analysis done, adoption open |

Headline result, with every number in `ml/README.md`:

| | v1 | v2 |
|---|---|---|
| Threshold | 0.70, chosen on **test** (biased) | 0.63, chosen on **validation** |
| Precision | 0.977 | 0.970 |
| Recall | 0.916 | 0.923 |
| Across 3 seeds | — | precision 0.975 ± 0.008, recall 0.897 ± 0.011 |

**v2 holds v1's performance while being measured honestly.** That is the
answer to the feedback: not a bigger number, a defensible one.

---

## Already done — do not redo

| Technique | Where |
|---|---|
| Transfer learning from an ImageNet-21k checkpoint | `vit_base_patch16_224_imagenet21k` via KerasHub |
| Two-phase fine-tune (freeze head → unfreeze at 1e-5) | `notebooks/finetune_vit.ipynb` |
| Leakage-free split by perceptual hash, stratified, seeded | `prepare_dataset.py` |
| De-duplication (69 near-duplicates removed) | `prepare_dataset.py` |
| Threshold sweep with an explicit precision target | `select_threshold.py` |
| Cost-asymmetry reasoning for the operating point | `README.md` |
| Re-scoring through the backend's own inference path | `artifacts/*_scores_backend.csv` |
| RandomResizedCrop, RandAugment-style policy, camera degradations, erasing | notebook cell 9 |
| Precision/recall/PR-AUC metrics on the positive column | notebook cell 11 |
| PR-AUC early stopping with `mode='max'`, label smoothing 0.1 | notebook cells 11–15 |
| Validation-first threshold selection, run end to end | `artifacts/val_threshold_v2.txt` → `test_threshold_v2.txt` |
| Seed variance, and the sampling noise it cannot explain | `aggregate_seeds.py`, `artifacts/seed_study.txt` |

Any plan that proposes these is proposing work that is finished.

---

## 1. The threshold — DONE

The old 0.70 was selected by sweeping `test_scores_backend.csv`, the **held-out
test split**, and then reporting test metrics at that point. That is
optimistically biased: the threshold was fitted to the same 293 images the
result was claimed on, so 0.977 was an upper bound on itself.

The correct procedure is now implemented **and run**:

- `score_split.py` scores any split through `inference.score_images`, the
  backend's own entry point.
- `select_threshold.py` defaults to the validation scores and warns when asked
  to sweep a file whose name contains `test`.
- `--at-threshold` reports at a frozen value and offers no choice, so the
  reporting step cannot quietly become a second selection step.

v2's operating point was selected on validation (`val_threshold_v2.txt`,
recommending **0.6300**) and reported once on test (`test_threshold_v2.txt`).
`backend/.env`, `.env.example` and `config.py` all carry 0.63.

Test precision came out at 0.970 against v1's 0.977. **That is the honest
number, not a regression** — and it is worth more marks than a higher number
obtained the old way.

---

## 2. Augmentation — DONE, except Mixup and CutMix

The old recipe was horizontal flip plus brightness/contrast/saturation jitter:
a light CNN-era pipeline for a ViT-Base on 1,358 images, and one that did not
rehearse the domain gap the README names.

Notebook cell 9 now implements, in `tf.image`:

| Technique | Why here | State |
|---|---|---|
| RandomResizedCrop, scale 0.6–1.0 | Rehearses subject distance — the main domain gap | ✅ |
| Random horizontal flip | Kept from the old recipe | ✅ |
| RandAugment-style policy, N=2 ops | Replaces three hand-tuned constants with a sampled policy | ✅ |
| Gaussian blur, motion blur, downscale, JPEG | Rehearses phone-camera conditions | ✅ |
| Random erasing | Occlusion robustness (hands, phones, crowds) | ✅ |
| Mixup + CutMix | The other half of the DeiT recipe | ❌ **still outstanding** |

Two deliberate departures from the plan as first written:

**Hand-rolled `tf.image`, not `keras_cv`.** keras-cv is in maintenance and its
co-install with Keras 3 and keras-hub is fragile on Colab; a broken import at
the top of a training run costs more than the citation is worth. The policy is
therefore *RandAugment-style* — N ops sampled at a shared magnitude — and not
the published op list, which the report should say. Cite arXiv:1909.13719 for
the method, not for this implementation.

**Mixup and CutMix remain outstanding.** They produce soft labels that interact
with the label smoothing in §3, so their effect is worth measuring on its own
row of the results table rather than bundled in with everything else. This is
the largest single item left on the training side.

---

## 3. What training measures — DONE

`metrics=['accuracy']` and `EarlyStopping(monitor='val_loss')` meant the
retained checkpoint was the one with the best loss, not the one that serves S10
best. Cell 11 now compiles with precision, recall and PR-AUC, and both training
stages early-stop on `val_pr_auc` with `mode='max'`.

Two things that are easy to get wrong here, and are handled:

**The metrics read the positive-class column.** `keras.metrics.Precision` on a
2-column softmax compares the whole output against the whole target, averaging
the positive class with its own complement. The notebook wraps Precision,
Recall and AUC to slice `[:, POSITIVE_INDEX]` first.

**`mode='max'` is not optional.** With the default `mode='auto'` on an
unrecognised metric name, Keras can minimise PR-AUC and restore the worst
weights of the run.

Label smoothing (`label_smoothing=0.1`) went in at the same time, forcing the
loss to `CategoricalCrossentropy` and the labels to one-hot. Smoothing is
applied inside the loss, so the metrics still see clean 0/1 targets.

Measured PR-AUC: **0.988 ± 0.001** across seeds.

---

## 4. One run is not a result — DONE

Notebook section 11 retrains the recipe at seeds 1, 2 and 3;
`ml/aggregate_seeds.py` puts each seed through the whole procedure
independently — threshold selected on that seed's own validation split, test
metrics reported at that frozen threshold — then prints mean ± SD.

| | Mean ± SD across 3 seeds |
|---|---|
| Precision | 0.975 ± 0.008 |
| Recall | 0.897 ± 0.011 |
| F1 | 0.934 ± 0.004 |
| PR-AUC | 0.988 ± 0.001 |
| Threshold | 0.640 ± 0.044 |

**Quote the spread, not the single run.** The deployed checkpoint's recall of
0.923 sits 2.4 SD above the seed mean of 0.897, so it is a favourable draw;
its precision and threshold are both within 1 SD.

### The other half of the uncertainty

Seeds are not the only reason a number moves. With 151 non-smoking test images
the 95% interval on precision is about **±0.032**, against a seed-to-seed SD of
**±0.008** — so the test split dominates by roughly four times, and **averaging
over seeds cannot shrink it.** Only more labelled test data can.

`select_threshold.py --at-threshold` prints Wilson intervals beside the point
estimates, and `aggregate_seeds.py` compares the two sources and says which
dominates. Report both: a supervisor asking "how much of this is luck?" is
asking about both, and quoting only the seed spread answers half the question.

---

## 5. Calibration — OUTSTANDING

Scores still cluster at the extremes, which usually means the network is
over-confident: a raw 0.95 does not mean 95% likely to be correct. This matters
because the confidence is surfaced to the administrator on D05 as decision
support, and stored per report in `REPORT_PHOTO.confidence_score`.

Fit a single temperature scalar on the validation split (Guo et al.,
arXiv:1706.04599) and apply it at inference. One parameter, ~20 lines, and it
makes the number mean what it appears to mean.

Label smoothing has already tempered the distribution somewhat, so measure the
expected calibration error before and after rather than assuming the gain.

**This is the most valuable item left**, because it improves what an
administrator sees without touching the model or the operating point.

---

## 6. Cheap inference-time gains — PARTLY ANALYSED

- **Test-time augmentation** — average the score over the image and its
  horizontal flip. One extra forward pass per photograph. ❌ not done.
- **Hard negatives** — the corpus contains some confusable non-smoking
  gestures, but more (phone to ear, drinking, vaping, pen) would attack the
  remaining false positives directly. ❌ not done; needs new labelled images.
- **Report-level rule** — ✅ **computed**. `select_threshold.py` now prices the
  ≥2-of-3 rule at the chosen threshold and prints it beside the ≥1 rule. At
  0.63 on validation it takes invalid reports reaching enforcement from 2.00%
  to 0.01%, at the cost of rejecting 1.44% of genuine reports. **The analysis
  is done; adopting it is a §8 design decision, not an ML one** — and it needs
  no model change or retraining.

---

## Order of remaining work

1. **Calibrate** (§5) — best value for the effort, and it is what D05 shows.
2. **Mixup and CutMix** (§2) — the last untried training technique, on its own
   row of the results table.
3. **TTA** (§6) — cheap, one extra forward pass.
4. **Decide on ≥2-of-3** (§6) — a design call; the numbers are already there.
5. **Hard negatives** (§6) — highest cost, needs new labelled data.

Keep a results table, one row per change, precision and recall before and
after. That table is the answer to "what techniques did you add" — it turns a
list of citations into evidence.

---

## Sources

- [facebookresearch/deit](https://github.com/facebookresearch/deit) · [arXiv:2012.12877](https://arxiv.org/abs/2012.12877) — augmentation recipe for ViTs on small data
- [keras-team/keras-cv](https://github.com/keras-team/keras-cv) — RandAugment, MixUp, CutMix as Keras layers
- [albumentations](https://github.com/albumentations-team/albumentations) — blur, compression, downscale transforms
- [Guo et al., arXiv:1706.04599](https://arxiv.org/abs/1706.04599) — temperature scaling
- [Szegedy et al., arXiv:1512.00567](https://arxiv.org/abs/1512.00567) — label smoothing
- [scikit-learn — tuning the decision threshold](https://scikit-learn.org/stable/modules/classification_threshold.html)
- [Khan et al. (2023), SmokerViT, CMC 77(1)](https://www.techscience.com/cmc/v77n1/54461)
