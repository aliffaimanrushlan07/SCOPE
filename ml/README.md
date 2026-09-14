# SCOPE — AI classification module

The evidence classifier used at **S10**. Given a photograph, it returns
P(smoking violation); the backend compares that against a configurable
threshold and accepts the report when at least one photograph clears it.

---

## Status — complete

| Step | State |
|---|---|
| Tooling (`prepare_dataset.py`, `select_threshold.py`, notebook) | ✅ |
| Dataset assembled and split | ✅ 1,941 images |
| Model fine-tuned | ✅ `vit-scope-v1` |
| Threshold chosen | ⚠️ **0.70**, but selected on the test split — [re-select on validation](#5-threshold) |
| Wired into the backend | ✅ real inference, stub removed |

---

## Results

Fine-tuned `vit_base_patch16_224_imagenet21k` on 1,358 training images,
validated on 290, and evaluated **once** on 293 held-out test images.

| Metric at threshold 0.70 | Value |
|---|---|
| Precision | **0.977** |
| Recall | **0.916** |
| F1 | 0.945 |
| Accuracy | 0.949 |
| Confusion | TP 130 · FP 3 · FN 12 · TN 148 |

Mean score for smoking images **0.939**, for non-smoking **0.055** — a
separation of 0.884, meaning the model is decisive rather than hedging.

> **These figures are optimistically biased and will change.** The 0.70
> threshold was selected by sweeping these same test scores, so the operating
> point was fitted to the images the result is claimed on. The tooling for the
> correct procedure — select on validation, report on test — is in place
> (`score_split.py`, and `select_threshold.py --at-threshold`); the numbers
> above are re-measured the next time the model is trained. Expect precision to
> fall slightly. That is the honest figure, not a regression.

### Threshold sweep

| Threshold | Precision | Recall | F1 | TP | FP | FN | TN |
|---|---|---|---|---|---|---|---|
| 0.10 | 0.892 | 0.993 | 0.940 | 141 | 17 | 1 | 134 |
| 0.20 | 0.928 | 0.993 | 0.959 | 141 | 11 | 1 | 140 |
| 0.30 | 0.945 | 0.965 | 0.955 | 137 | 8 | 5 | 143 |
| 0.33 | 0.951 | 0.965 | 0.958 | 137 | 7 | 5 | 144 |
| 0.50 | 0.964 | 0.951 | 0.957 | 135 | 5 | 7 | 146 |
| **0.70** | **0.977** | **0.916** | **0.945** | **130** | **3** | **12** | **148** |
| 0.80 | 0.977 | 0.901 | 0.938 | 128 | 3 | 14 | 148 |
| 0.90 | 0.976 | 0.873 | 0.922 | 124 | 3 | 18 | 148 |
| 0.95 | 0.992 | 0.866 | 0.925 | 123 | 1 | 19 | 150 |

---

## Why 0.70 and not the best-F1 point

`select_threshold.py` recommends **0.33** — the highest recall that still
holds precision at 0.95, and close to the best-F1 point. **0.70 was chosen
instead**, and the reasoning matters more than the number.

### The ≥1-photo rule changes the arithmetic

A report passes when **any one** of up to three photographs clears the
threshold (§8). So a false positive gets **three independent chances** per
report, while a false negative requires **all three** photographs to fail.
Per-photo metrics do not show this.

| Threshold | Per-photo FPR | Per-photo FNR | **Invalid report accepted** | **Genuine 3-photo report rejected** |
|---|---|---|---|---|
| 0.33 | 4.64% | 3.52% | **13.27%** | 0.004% |
| 0.50 | 3.31% | 4.93% | 9.61% | 0.012% |
| **0.70** | **1.99%** | **8.45%** | **5.84%** | **0.060%** |
| 0.90 | 1.99% | 12.68% | 5.84% | 0.204% |
| 0.95 | 0.66% | 13.38% | 1.97% | 0.240% |

Moving from 0.33 to 0.70 **more than halves** the rate at which an invalid
report reaches enforcement, while the chance of wrongly rejecting a genuine
three-photograph report stays below one in a thousand.

### Why not higher

0.95 looks better still — until you notice its 0.66% false-positive rate rests
on **exactly one** misclassified image out of 151. A rate estimated from a
single sample is not a measurement. 0.70 sits on a **plateau**: the
false-positive rate is 1.99% at 0.70, 0.80 and 0.90 alike, so small errors in
the estimate do not move the operating point. It is a shelf, not a cliff edge.

0.95 would also reject 13.4% of genuine single-photograph reports, and many
reporters will take only one photograph.

### The asymmetry this reflects

§S10 requires the operating point to keep **false positives** low. The two
errors do not cost the same:

- A **false positive** forwards an invalid report to enforcement. Administrators
  are read-only and the AI decision is final, so nothing downstream catches it.
- A **false negative** asks the reporter to retake a photograph. Recoverable,
  and they are standing there.

---

## Reproducing this

### 1. Data

[Kaggle / Mendeley smoking-vs-not-smoking corpus](https://data.mendeley.com/datasets/7b52hhzs3r/1)
— **CC BY 4.0**, attribution required. Cite it in Chapter 5.

Downloaded as `training_data/` + `validation_data/` + an unlabelled
`testing_data/`. The unlabelled folder is unusable and was discarded; the two
labelled folders were **merged and re-split from scratch** rather than reusing
the publisher's split, because that split was not verified leakage-free — and
in fact 69 duplicate images were found spanning it.

```
ml/data/raw/smoking/       1,005 images
ml/data/raw/notsmoking/    1,005 images
```

### 2. Split

```bash
./backend/.venv/bin/python ml/prepare_dataset.py
```

| Split | smoking | notsmoking | Total |
|---|---|---|---|
| train | 660 | 698 | 1,358 |
| val | 141 | 149 | 290 |
| test | 142 | 151 | 293 |
| **Total** | **943** | **998** | **1,941** |

69 duplicates removed by perceptual hash. Whole hash groups are assigned to a
single split, so near-identical frames cannot straddle train and test. Seeded
and reproducible; splitting happens before augmentation.

### 3. Bundle for Colab

```bash
./backend/.venv/bin/python ml/make_colab_bundle.py
```

453 MB → 23 MB by resizing to 256 px, which the model would do anyway.

### 4. Train

`ml/notebooks/finetune_vit.ipynb` in Google Colab, Runtime → **T4 GPU**.

Two stages: freeze the backbone and train the head, then unfreeze and
fine-tune at a lower learning rate.

> **`activation='softmax'` is required and is not the default.** KerasHub ships
> `activation=None`, which returns raw logits. Pairing that with
> `from_logits=False` silently trains against a broken objective — the first
> run here did exactly that and produced negative "confidence" scores no
> threshold could act on. The notebook now asserts the output range immediately
> after building the model, before a training run is spent.

Uses **KerasHub**, not HuggingFace `transformers`, which has removed
TensorFlow support entirely — `TFViTForImageClassification` no longer exists.
KerasHub is Keras-native on the TensorFlow backend, so Table 3.5 stays accurate
and no PyTorch is involved.

### 5. Threshold

Two steps, in this order. They are not interchangeable.

```bash
# SELECT on validation — this is where the operating point is chosen
./backend/.venv/bin/python ml/score_split.py val
./backend/.venv/bin/python ml/select_threshold.py ml/artifacts/val_scores_backend.csv

# REPORT on test at the threshold that came back, changing nothing
./backend/.venv/bin/python ml/score_split.py test
./backend/.venv/bin/python ml/select_threshold.py \
    ml/artifacts/test_scores_backend.csv --at-threshold <frozen>
```

The threshold is a parameter fitted to data, like a weight. Fitting it on the
test split and then reporting test metrics at that point measures the model on
images the operating point was chosen to suit — the precision that comes back
is an upper bound on itself rather than an independent estimate. Sweeping a
file whose name contains `test` now prints a warning for exactly this reason.

If the threshold is adjusted after seeing the test figures, the test split has
been spent and the number is no longer independent. Change the model instead,
or state plainly in Chapter 5 that the split was reused.

Scores are recomputed **through the backend's own inference code** — the
`score_images` entry point that serves S10 — not taken from the notebook.
Resizing with PIL instead of TensorFlow shifted individual scores by up to
**0.46**, which would have silently invalidated the calibration.

### 6. Backend

```
AI_MODEL_PATH=../ml/artifacts/vit-scope-v1.keras
AI_MODEL_VERSION=vit-scope-v1
AI_CONFIDENCE_THRESHOLD=0.70
AI_STUB_MODE=false
```

The model loads once at application startup. The threshold is read per request,
so it can be retuned without rebuilding the mobile app — which is what §S10
requires.

---

## Limitations to state honestly in the report

**Domain gap.** The training images are web-sourced photographs, not phone
photos taken at a distance in a Malaysian food court. Real submissions will be
further from the camera, more motion-blurred, and worse lit. Measured accuracy
on this test set is an **upper bound** on field performance.

**Failure reasons are heuristic.** The model is a single-label classifier: it
reports how confident it is that a violation is present, not *why* it is
unconvinced. The "too blurry" / "too far" messages are presentational bands
over the confidence score, not measurements. Deriving blur from a Laplacian
variance check and distance from a detection bounding box would make them real.

**No human check.** FR12 was removed, so a false positive reaches enforcement
uncorrected. The defence is that the threshold is tuned to minimise exactly
that (3 false positives in 151 non-violations), and the dashboard is advisory —
it informs patrol planning rather than triggering enforcement against a named
party.

**Single evaluation run.** The test split was used once. Figures are not
averaged over repeated runs with different seeds, so they carry the variance of
a single training run.

**The published threshold was selected on the test split.** Until the model is
retrained and the validation-first procedure in section 5 is run end to end,
the reported precision of 0.977 is an upper bound on itself. The procedure is
implemented; the figures are not yet re-measured under it.

---

## Files

| Path | Purpose |
|---|---|
| `prepare_dataset.py` | De-duplicate, split, manifest |
| `make_colab_bundle.py` | Resize + zip for upload |
| `score_split.py` | Score a split through the backend's inference code |
| `select_threshold.py` | Threshold selection (val) and reporting (test) |
| `notebooks/finetune_vit.ipynb` | Training |
| `data/manifest.csv` | The authoritative split (gitignored) |
| `data/report.md` | Composition table for Chapter 5 |
| `artifacts/vit-scope-v1.keras` | Trained model, ~982 MB (gitignored) |
| `artifacts/val_scores_backend.csv` | Scores the threshold is SELECTED on |
| `artifacts/test_scores_backend.csv` | Scores the threshold is REPORTED on |
