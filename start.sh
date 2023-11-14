
cd examples/whisper.swiftui/

echo "Opening xcode..."
open whisper.swiftui.xcodeproj/

echo "Download model from https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-base.bin and add here."
cd whisper.swiftui.demo/Resources/models 
open .

echo "Done"