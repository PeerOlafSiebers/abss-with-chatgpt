"""
Automate EABSS conversations with Google Gemini 2.5 Pro
As of July 2025, Free tier of Google Gemini 2.5 Pro API restricts requests per minute, see `throttle(...)` below.
Usage example:
python gemini_eabss_automation_bot.py --model gemini-2.5-pro --prompt-filepath streamlining_eabss_3_advanced_model_script.json --temperature 0.9 --top-p 0.9 --verbose
"""

import argparse, json, os, time
from dotenv import load_dotenv                          # pip install -U google-genai>=1.0.0                  # SDK type helpers
import google.generativeai as genai
# ---------- env + CLI ----------
load_dotenv()
api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    raise SystemExit(
        "GEMINI_API_KEY is missing.\n"
        "Create a .env file that contains a line like:\n"
        "GEMINI_API_KEY=AIza..."
    )

parser = argparse.ArgumentParser(description="Automate chatbot communication with Gemini models")
parser.add_argument("--model", type=str, required=True, help="Name of the model to use")
parser.add_argument("--prompt-filepath", type=str, required=True, help="File path to JSON file that stores prompts (path should be relative to the directory from where this script is called)")
# optional flags
parser.add_argument("--temperature", type=float, help="Sampling temperature")
parser.add_argument("--top-p", type=float, help="Nucleus sampling top-p")
parser.add_argument("--verbose", action="store_true", help="Print prompt/completion token counts and running total after each reply")

args = parser.parse_args()

MODEL_NAME   = args.model
PROMPT_FILE  = args.prompt_filepath
TEMP         = args.temperature
TOP_P        = args.top_p
VERBOSE      = args.verbose

# ---------- client ----------
genai.configure(api_key=api_key)

# build once so we can re‑use a single chat session
gen_cfg_kwargs = {}
if TEMP is not None:
    gen_cfg_kwargs["temperature"] = TEMP
if TOP_P is not None:
    gen_cfg_kwargs["top_p"] = TOP_P

model = genai.GenerativeModel(
    MODEL_NAME,
    **(
        {"generation_config": genai.types.GenerationConfig(**gen_cfg_kwargs)}
        if gen_cfg_kwargs
        else {}
    )  
)
chat = model.start_chat(
    history=[
        {"role": "user", "parts": ["You are an assistant that must assist the user"]}
    ]
)

# ---------- helpers ----------
FREE_RPM          = 5                             # free‑tier limit
MIN_INTERVAL_SEC  = 60.0 / FREE_RPM               # 12 s
_last_request_ts  = 0.0

def throttle():
    global _last_request_ts
    now = time.time()
    delta = now - _last_request_ts
    if delta < MIN_INTERVAL_SEC:
        time.sleep(MIN_INTERVAL_SEC - delta)
    _last_request_ts = time.time()

def ask_user_inputs():
    injects = {
        "{INJECT_CHATBOT}":           "Gemini 2.5 Pro",
        "{INJECT_CHATBOT_COMPANY}":   "Google",
        "{INJECT_TOPIC}": input("Please enter the topic (a summary upto 100 words of the topic. Possibly covering: \"who, what, where, when, why and how\"): "),
        "{INJECT_RESEARCHDESIGN}": input("Please enter the research design (e.g. \"Exploratory\"): "),
        "{INJECT_DOMAIN}": input("Please enter the domain (e.g. \"Ecological Modelling\"): "),
        "{INJECT_SPECIALISATION}": input("Please enter the specialisation (e.g. \"Ecological Dynamics\"): "),
        "{INJECT_DOMAIN_RELATED_ROLE}": input("Please enter the role associated with the domain (e.g. \"Sociologist, Economist, Ecologist\"): ")
    }
    return injects

injectable_prompts = ask_user_inputs()

def build_prompt(text: str) -> str:
    for tag, val in injectable_prompts.items():
        text = text.replace(tag, val)
    return text

# ---------- main ----------
def run_conversation(path: str, verbose=False):
    with open(path, encoding="utf-8") as fp:
        script_lines = json.load(fp)          # list of {prompt_name: prompt_text}

    prompt_output_map   = {}
    prompt_name_out_map = {}
    prev_prompt_tokens = 0
    total_in = total_out = 0

    for line in script_lines:
        for prompt_name, prompt in line.items():
            prompt = build_prompt(prompt)

            if prompt_name.startswith("reminder_"):
                key = prompt_name.split("_")[-1]
                prompt += prompt_name_out_map.get(key, "")

            print(prompt, "\n>>>")

            throttle()                        # stay under 5 RPM

            response = chat.send_message(prompt)
            content  = response.text.strip()
            usage    = response.usage_metadata or {}

            # -------- bookkeeping --------
            prompt_output_map[prompt]         = content
            prompt_name_out_map[prompt_name]  = content

            # Gemini returns cumulative prompt_token_count per request
            cum_prompt = getattr(usage, "prompt_token_count", 0)
            turn_in    = cum_prompt - prev_prompt_tokens
            prev_prompt_tokens = cum_prompt

            turn_out   = getattr(usage, "candidates_token_count", 0)
            total_in  += turn_in
            total_out += turn_out

            print(content)

            if verbose:
                grand_total = total_in + total_out
                print(f"\ninput tokens this turn: {turn_in}, "
                      f"total input so far: {total_in} | "
                      f"output tokens this turn: {turn_out}, "
                      f"total output so far: {total_out}\n"
                      f"grand total so far: {grand_total}")

            print("\n" + "-"*40 + "\n")

    ts = time.strftime("%Y%m%d-%H%M%S")
    with open(f"{MODEL_NAME}_run_{ts}.json", "w", encoding="utf-8") as fp:
        json.dump(prompt_output_map, fp, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    run_conversation(PROMPT_FILE, VERBOSE)
