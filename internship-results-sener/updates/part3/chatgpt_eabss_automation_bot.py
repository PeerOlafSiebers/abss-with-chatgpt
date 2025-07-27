"""
Automate EABSS conversations with OpenAI ChatGPT

Usage example:
python chatgpt_eabss_automation_bot.py --model o4-mini-2025-04-16 --prompt-filepath streamlining_eabss_3_advanced_model_script.json --temperature 0.9 --top-p 0.9 --verbose
"""

import argparse, json, os, time
from dotenv import load_dotenv
import openai                    # pip install --upgrade openai>=1.25.0

load_dotenv() # looks for .env in current working directory and stores as os vars
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    raise SystemExit(
        "OPENAI_API_KEY is missing.\n"
        "Create a .env file that contains a line like:\n"
        "OPENAI_API_KEY=sk-..."
    )
openai.api_key = api_key

parser = argparse.ArgumentParser(description="Automate chatbot communication with OpenAI models")
parser.add_argument("--model", type=str, required=True, help="Name of the model to use")
parser.add_argument("--prompt-filepath", type=str, required=True, help="File path to JSON file that stores prompts (path should be relative to the directory from where this script is called)")
# optional flags
parser.add_argument("--temperature", type=float, help="Sampling temperature")
parser.add_argument("--top-p", type=float, help="Nucleus sampling top-p")
parser.add_argument("--verbose", action="store_true", help="Print prompt/completion token counts and running total after each reply")
args = parser.parse_args()

MODEL_NAME = args.model
PROMPT_FILEPATH = args.prompt_filepath
TEMPERATURE = args.temperature
TOP_P = args.top_p
VERBOSE = args.verbose

def build_chat_params():
    params = {}
    if TEMPERATURE is not None:
        params["temperature"] = TEMPERATURE
    if TOP_P is not None:
        params["top_p"] = TOP_P
    return params

# stores user's responses that are fundamentally necessary e.g. topic of the current EABSS study, these responses (strings) are injected into the prompt
injectable_prompts = {
    "{INJECT_CHATBOT}":"ChatGPT",
    "{INJECT_CHATBOT_COMPANY}": "OpenAI",
    "{INJECT_TOPIC}": None,
    "{INJECT_RESEARCHDESIGN}": None,
    "{INJECT_DOMAIN}":None,
    "{INJECT_SPECIALISATION}":None,
    "{INJECT_DOMAIN_RELATED_ROLE}":None
}

injectable_prompts["{INJECT_TOPIC}"] = input("Please enter the topic (a summary upto 100 words of the topic. Possibly covering: \"who, what, where, when, why and how\"): ")
injectable_prompts["{INJECT_RESEARCHDESIGN}"] = input("Please enter the research design (e.g. \"Exploratory\"): ")
injectable_prompts["{INJECT_DOMAIN}"] = input("Please enter the domain (e.g. \"Ecological Modelling\"): ")
injectable_prompts["{INJECT_SPECIALISATION}"] = input("Please enter the specialisation (e.g. \"Ecological Dynamics\"): ")
injectable_prompts["{INJECT_DOMAIN_RELATED_ROLE}"] = input("Please enter the role associated with the domain (e.g. \"Sociologist, Economist, Ecologist\"): ")

def run_conversation(path, verbose=False):
    with open(path, encoding="utf-8") as fp:
        lines = json.load(fp)          # expects list of {prompt_name: prompt_text}

    msgs                  = [{"role":"system","content":"You are an assistant that must assist the user"}]
    prompt_output_map     = {}
    prompt_name_out_map   = {}
    prev_prompt_total = 0
    total_in = 0
    total_out = 0

    chat_params = build_chat_params()

    for line in lines:
        for prompt_name, prompt in line.items():
            # inject values
            for tag, value in injectable_prompts.items():
                prompt = prompt.replace(tag, value)

            if prompt_name.startswith("reminder_"):
                key = prompt_name.split("_")[-1]
                prompt += prompt_name_out_map.get(key, "")

            print(prompt, "\n>>>")

            msgs.append({"role": "user", "content": prompt})
            response = openai.chat.completions.create(
                model     = MODEL_NAME,
                messages  = msgs,
                **chat_params
            )

            content      = response.choices[0].message.content
            usage        = response.usage                   # prompt_tokens / completion_tokens / total_tokens
            msgs.append({"role":"assistant","content": content})

            # bookkeeping
            prompt_output_map[prompt]     = content
            prompt_name_out_map[prompt_name] = content

            turn_in = usage.prompt_tokens - prev_prompt_total # subtract because usage.prompt_tokens is cumulative
            turn_out = usage.completion_tokens

            prev_prompt_total = usage.prompt_tokens

            total_in  += turn_in
            total_out += turn_out

            print(content)

            if verbose:
                grand_total = total_in + total_out
                print(f"\n\ninput tokens used this turn: {turn_in}, "
                      f"total input tokens used so far: {total_in} | "
                      f"output tokens used this turn: {turn_out}, "
                      f"total output tokens used so far: {total_out}\n"
                      f"total tokens used so far: {grand_total}")

            print("\n\n\n" + "-"*40 + "\n\n\n")

    ts = time.strftime("%Y%m%d-%H%M%S")
    with open(f"{MODEL_NAME}_run_{ts}.json", "w", encoding="utf-8") as fp:
        json.dump(prompt_output_map, fp, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    run_conversation(PROMPT_FILEPATH, VERBOSE)
