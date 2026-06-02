/* Gives SwiftPM a compilable source so CWhisper is a buildable C target.
   The real symbols come from the prebuilt static libs linked in Package.swift. */
#include "whisper.h"
