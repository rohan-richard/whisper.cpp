import streamlit as st
import json
import websockets
import asyncio
import base64

ELEVENLABS_API_KEY = 'YOUR KEY'
VOICE_ID = 'S6JMST0dI5MnHb6gPvFI'

st.title("Text-to-Speech Streamlit App")
user_input = st.text_area("Enter text for TTS:")

if st.button("Stream Audio"):
    async def stream_audio():
        uri = f"wss://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}/stream-input?model_id=eleven_monolingual_v1"

        async with websockets.connect(uri) as websocket:
            await websocket.send(json.dumps({
                "text": user_input,
                "voice_settings": {"stability": 0.5, "similarity_boost": True},
                "xi_api_key": ELEVENLABS_API_KEY,
            }))

            await websocket.send(json.dumps({"text": ""})) 

            audio_data = b''  # Variable to concatenate audio chunks

            async def listen():
                nonlocal audio_data
                """Listen to the websocket for audio data and concatenate it."""
                while True:
                    try:
                        message = await websocket.recv()
                        data = json.loads(message)
                        if data.get("audio"):
                            audio_chunk = base64.b64decode(data["audio"])
                            audio_data += audio_chunk
                        elif data.get('isFinal'):
                            break
                    except websockets.exceptions.ConnectionClosed:
                        print("Connection closed")
                        break

            await listen()
            st.audio(audio_data, format="audio/wav")

    asyncio.run(stream_audio())