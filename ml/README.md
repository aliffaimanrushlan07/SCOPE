# SCOPE — AI classification module

The evidence classifier used at **S10**. Given a photograph, it returns
P(smoking violation); the backend compares that against a configurable
threshold and accepts the report when at least one photograph clears it.

This is the project's principal technical contribution and the only component
whose duration cannot be predicted. Start it early.

---

## Status

| Step | State |
|---|---|
| Tooling (`prepare_dataset.py`, `select_threshold.py`, notebook) | ✅ built and tested |
| Dataset downloaded | ⬜ **you** — see below |
| Model fine-tuned | ⬜ |
| Threshold chosen | ⬜ — the one open item in §8 of the flow document |
| Wired into the backend | ⬜ — a stub is in place so the app already runs end to end |

---

## 1. Get the data

**You need to download these yourself.** Each requires accepting the host's
terms or holding an account, which is not something I can do on your behalf —
and the licence you agree to has to be one *you* are willing to cite.

### Recommended: Mendeley Data — "Smoking vs not-smoking"

| | |
|---|---|
| **Licence** | **CC BY 4.0** — free to use, including commercially, with attribution |
| **DOI** | `10.17632/7b52hhzs3r.1` |
| **Contributor** | Ali Khan |
| **Size** | 2,400 images — 1,200 smoking, 1,200 not-smoking (already balanced) |
| **URL** | <https://data.mendeley.com/datasets/7b52hhzs3r/1> |

The reason to prefer this one: its **negative class is deliberately hard**. It
contains people drinking, using inhalers, and holding phones to their face —
the exact gestures that a naive classifier mistakes for smoking. A model
trained against easy negatives scores well in a notebook and then fails in
front of your examiners.

**Attribution is a licence condition, not a courtesy.** Cite it in Chapter 5
and in your references.

### Supplementary options

| Source | Licence | Note |
|---|---|---|
| [Kaggle — Smoker Detection](https://www.kaggle.com/datasets/sujaykapadnis/smoking) | Check on the page | 1,120 images; overlaps heavily with the Mendeley set, so de-duplicate |
| [Roboflow Universe — smoking](https://universe.roboflow.com/browse/smoking) | Varies by dataset — several CC BY 4.0, some Public Domain | Object-detection datasets; export as **classification** folders |

Check the licence on the specific dataset page before downloading. Some
Roboflow datasets are Public Domain, others CC BY 4.0 — the requirement
differs and you must record which you used.

### The gap you should know about

None of these are photographs taken on a phone, at a distance, in a Malaysian
food court — which is what your app will actually receive. Your S10 failure
reasons ("subject too far", "image too blurry") describe conditions the
training data barely contains.

If you have time, photograph a few dozen realistic scenes yourself (a friend
holding an unlit cigarette is a perfectly good positive for framing purposes,
and an honest one to describe in the report). Even 50 in-domain images
noticeably improve real-world behaviour, and being able to say you addressed
the domain gap is a strong point at viva.

### Where to put it

```
ml/data/raw/smoking/*.jpg
ml/data/raw/notsmoking/*.jpg
```

Folder names must match exactly. `ml/data/` is gitignored — the image corpus
never enters the repository.

---

## 2. Prepare the split

```bash
./backend/.venv/bin/python ml/prepare_dataset.py
```

Writes `ml/data/manifest.csv` and `ml/data/report.md`.

What it does, and why each part matters:

- **De-duplicates by perceptual hash.** Web-scraped sets repeat images, often
  resized or re-encoded. A byte hash misses those; a difference hash catches
  them. A duplicate spanning train and test means testing on a memorised image.
- **Assigns whole hash groups to one split.** Near-identical frames can never
  straddle the train/test boundary.
- **Stratifies by class**, so the test set does not drift toward one label.
- **Splits before augmentation.** Augmenting first scatters variants of one
  source image across all three splits — the same leakage, better disguised.
- **Seeded**, so the split is reproducible and your reported accuracy is
  checkable by someone else.

`ml/data/report.md` is a composition table ready to paste into Chapter 5.

---

## 3. Fine-tune

Open `ml/notebooks/finetune_vit.ipynb` in **Google Colab**, set Runtime → T4
GPU, and work down the cells. On CPU an epoch takes hours; on a T4, minutes.

**A stack note worth knowing:** HuggingFace `transformers` has *removed*
TensorFlow support, so the commonly-cited `TFViTForImageClassification` no
longer exists. The notebook uses **KerasHub**, which is the Keras-native
replacement, runs on the TensorFlow backend, and keeps the project consistent
with Table 3.5 (*TensorFlow / Keras*). No PyTorch is involved.

Training is two-stage: freeze the backbone and train the new head, then
unfreeze and fine-tune at a much lower learning rate. Doing it in one stage
lets large random gradients from the untrained head destroy the pre-trained
features that make transfer learning work at all.

Outputs to download: `test_scores.csv`, `training_curves.png`,
`vit-scope-v1.keras`, `model_metadata.json`.

---

## 4. Choose the threshold

```bash
./backend/.venv/bin/python ml/select_threshold.py ml/artifacts/test_scores.csv
```

This resolves the one item `SCOPE-System-Flow-Revised.md` §8 leaves open, and
it is an **empirical result, not a design choice**.

It does *not* pick the best-F1 point, because the two errors do not cost the
same:

- A **false positive** forwards an invalid report to enforcement. Administrators
  are read-only and the AI decision is final, so nothing downstream catches it.
- A **false negative** asks a reporter to retake a photograph. Recoverable, and
  they are standing right there.

So it holds precision at or above a target (default 0.95) and takes the best
recall available under that constraint. Print the sweep table into Chapter 5 —
it is the evidence for the number you chose.

Then set it:

```
AI_CONFIDENCE_THRESHOLD=<recommended>
AI_MODEL_VERSION=vit-scope-v1
```

The backend reads the threshold per request, so it can be retuned later
without rebuilding the mobile app — which is what §S10 requires.

---

## 5. Wire it into the backend

Replace `_score_image` in `backend/app/services/inference.py`. The public
signature of `classify_photos` is the contract — nothing outside that file
changes, and the mobile app needs no rebuild.

Load the model **once at application startup**, never per request. Loading a
ViT per request makes S10 unusable.

---

## What to keep for Chapter 5

- `ml/data/report.md` — dataset composition and cleaning table
- `training_curves.png` — accuracy and loss, train vs validation
- The threshold sweep table from `select_threshold.py`
- The chosen threshold **and the reasoning for it**
- Dataset sources, licences, and attributions
