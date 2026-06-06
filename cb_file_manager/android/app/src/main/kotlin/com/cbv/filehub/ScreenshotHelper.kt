package com.cbv.filehub

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import java.io.ByteArrayOutputStream

object ScreenshotHelper {
    /**
     * Capture screenshot of an Android View
     * Used as fallback for video player screenshots
     */
    fun captureViewScreenshot(view: View): ByteArray? {
        return try {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            view.draw(canvas)
            
            // Convert bitmap to PNG bytes
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val bytes = stream.toByteArray()
            bitmap.recycle()
            
            bytes
        } catch (e: Exception) {
            android.util.Log.e("ScreenshotHelper", "Failed to capture screenshot: ${e.message}")
            null
        }
    }
}
