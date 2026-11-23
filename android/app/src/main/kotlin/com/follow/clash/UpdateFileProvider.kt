package com.follow.clash

import androidx.core.content.FileProvider

// A subclass keeps this manifest entry from merging with a library FileProvider.
class UpdateFileProvider : FileProvider()
