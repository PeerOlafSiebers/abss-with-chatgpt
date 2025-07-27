"""
A script to automate communication/conversation with chatbots
hosted in ollama.
"""

import ollama
import json
import os
import json
import time
import argparse

parser = argparse.ArgumentParser(description="Automate chatbot communication with Ollama")
parser.add_argument("--model", type=str, required=True, help="Name of the model to use")
parser.add_argument("--prompt-filepath", type=str, required=True, help="File path to JSON file that stores prompts (path should be relative to the directory from where this script is called)")
# optional flags
parser.add_argument("--temperature", type=float, help="Sampling temperature")
parser.add_argument("--repeat-penalty", type=float, help="Penalty applied to repeated tokens")
parser.add_argument("--verbose", action="store_true", help="Print prompt/completion token counts and running total after each reply")
args = parser.parse_args()

MODEL_NAME = args.model
PROMPT_FILEPATH = args.prompt_filepath
TEMPERATURE     = args.temperature
REPEAT_PENALTY  = args.repeat_penalty
VERBOSE = args.verbose

def make_chat_options():
    chat_options = {}
    if TEMPERATURE:
        chat_options["temperature"] = TEMPERATURE
    if REPEAT_PENALTY:
        chat_options["repeat_penalty"] = REPEAT_PENALTY
    return chat_options or None # return None if chat_options is empty (ie user wants default settings)

# stores user's responses that are fundamentally necessary e.g. topic of the current EABSS study, these responses (strings) are injected into the prompt
injectable_prompts = {
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

opts = make_chat_options()

# main automation logic 

def get_response(prompts_filepath, verbose=False):
    prompt_output_map = {}
    prompt_name_output_map = {}

    msgs = [] # conversation history - passed to ollama at every chat(...) method call

    with open(prompts_filepath, 'r', encoding='utf-8') as fp:
        data = json.load(fp)

    # track number of tokens
    prev_prompt_eval = 0  # number of tokens used in last input
    prev_eval = 0         # number of tokens used in last ouput
    # total number of input and output tokens used
    total_in = 0
    total_out = 0 
    
    for line in data:
        for prompt_name, prompt in line.items():
            for injectable in injectable_prompts.keys():
                if injectable in prompt:
                    prompt = prompt.replace(injectable, injectable_prompts[injectable])
            
            if prompt_name.startswith('reminder_'):
                key_of_remindable = prompt_name.split('_')[-1]
                prompt += prompt_name_output_map[key_of_remindable]
            
            print(prompt)

            print("\n")
            print(">>>")
            print("\n")

            msg = [
            {"role":"system", "content":"You are an assistant that must assist the user"},
            {"role":"user", "content":prompt},
            ]
            msgs.append(msg[1])
            if opts is None:
                output = ollama.chat(model=MODEL_NAME, messages=msgs)
            else:
                output = ollama.chat(model=MODEL_NAME, messages=msgs, options=opts)
            msgs.append(output['message'])
            prompt_output_map[prompt] = output["message"]["content"]
            prompt_name_output_map[prompt_name] = output["message"]["content"]

            print(output["message"]["content"])

            if verbose:
                prompt_eval = output.get("prompt_eval_count", 0) # if context window becomes full, ollama will trim the oldest tokens so this may shrink
                completion = output.get("eval_count", 0)

                input_tokens = prompt_eval - prev_prompt_eval - prev_eval

                total_in  += input_tokens
                total_out += completion
                grand_total = total_in + total_out

                prev_prompt_eval = prompt_eval
                prev_eval = completion

                print(
                        f"\n\nprompt (input) tokens used this turn: {input_tokens}. prompt tokens used so far: {total_in}. | completion (output) tokens used this turn : {completion}. completion tokens used so far: {total_out}.\ntotal tokens used so far: {grand_total}")
            print("\n\n\n---------------------------------------\n\n\n")

    timestr = time.strftime("%Y%m%d-%H%M%S")

    with open(f'{MODEL_NAME}_test_{timestr}.json', 'w') as fp:
        json.dump(prompt_output_map, fp)

    return

# call to automation logic. confirm the correct json filename is passed here.
get_response(PROMPT_FILEPATH, VERBOSE)
