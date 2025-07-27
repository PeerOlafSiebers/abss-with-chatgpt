import os
from posixpath import split

from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyPDFLoader
from langchain_community.embeddings.sentence_transformer import SentenceTransformerEmbeddings
from langchain_community.vectorstores import Chroma
from langchain.chains import RetrievalQA
from langchain.memory import ConversationSummaryMemory
from langchain.prompts import PromptTemplate
from langchain.llms import Ollama 
from langchain import hub
from langchain.callbacks.manager import CallbackManager
from langchain.callbacks.streaming_stdout import StreamingStdOutCallbackHandler
from langchain_core.prompts.chat import ChatPromptTemplate, HumanMessagePromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough

import streamlit as st

# load docs
# resources need to be loaded in StreamLit cache, else everything will be reloaded for each query
@st.cache_resource
def load_and_process_pdfs(folder_path):
    docs = []
    for file in os.listdir(folder_path):
        if file.endswith('.pdf'):
            pdf_path = os.path.join(folder_path, file)
            loader = PyPDFLoader(pdf_path)
            docs.extend(loader.load())
            
    # split text into chunks, to keep within input size limits (chunk_size is #chars)
    # chunk overlap allows us to keep context across chunks       
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000,chunk_overlap=200)
    splits = text_splitter.split_documents(docs)
    return splits

@st.cache_resource
def initialise_vectorstore(_splits):
    return Chroma.from_documents(splits, embedding=embedding_func)

embedding_func = SentenceTransformerEmbeddings(model_name="all-MiniLM-L6-v2") # chroma default embedding model, proven to work

splits = load_and_process_pdfs("./news-summaries-pdf")

vectorstore = initialise_vectorstore(splits)

# prompt template
llm = Ollama(
model="llama3:8b",
callback_manager=CallbackManager(
            [StreamingStdOutCallbackHandler()]
),
stop=["<|eot_id|>"],
)

prompt_template = ChatPromptTemplate(
    input_variables=['context', 'question'],
    messages=[
        HumanMessagePromptTemplate(
            prompt=PromptTemplate(
                input_variables=['context', 'question'],
                template="You are an assistant for question-answering tasks. Use the following pieces of retrieved context to help answer the question. If you don't know the answer, just say that you don't know. Keep the answer concise.\nQuestion: {question} \nContext: {context} \nAnswer:"
            )
        )
    ]
)

def format_docs(docs):
    return "\n\n".join(doc.page_content for doc in docs)

rag_chain = (
    {"context": vectorstore.as_retriever() | format_docs, "question": RunnablePassthrough()}
    | prompt_template
    | llm
    | StrOutputParser()
)

# streamlit app
st.title("Generative AI for Agent-based Simulation Modelling")

# init chat history
if "messages" not in st.session_state:
    st.session_state.messages = []

# display messages from prev sessions on app rerun
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])    

# react to user input
if prompt := st.chat_input("How can I help?"):
    # display user message in chat message container
    st.chat_message("user").markdown(prompt)
    # add user message to chat history
    st.session_state.messages.append({"role": "user", "content": prompt})

    try:
        response = rag_chain.invoke(prompt)
        st.write(response)

        # add assistant response to chat history
        st.session_state.messages.append({"role": "assistant", "content": response})    
    except Exception as e:
        st.error(f"The following error occured: {e}")