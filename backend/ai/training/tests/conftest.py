import sys
from pathlib import Path

# Add backend/ai/ to sys.path so `training` package can be imported absolutely.
# __file__ is backend/ai/training/tests/conftest.py
# parents[0] = tests/
# parents[1] = training/
# parents[2] = ai/           <-- this is what we want on sys.path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
