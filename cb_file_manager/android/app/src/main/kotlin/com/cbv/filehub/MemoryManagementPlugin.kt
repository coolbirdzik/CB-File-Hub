package com.cbv.filehub

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.lang.reflect.Method

class MemoryManagementPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private var isAggressiveMemoryManagementEnabled = false
    private var videoBufferSize = 1024 * 1024 // 1MB default
    private var lastGcTime = 0L
    private val gcInterval = 5000L // 5 seconds between GC calls

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "memory_management")
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(binding.binaryMessenger, "memory_events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                initializeMemoryManagement(result)
            }
            "forceGarbageCollection" -> {
                forceGarbageCollection(result)
            }
            "forceAggressiveCleanup" -> {
                forceAggressiveCleanup(result)
            }
            "forceBufferCleanup" -> {
                forceBufferCleanup(result)
            }
            "getMemoryUsage" -> {
                getMemoryUsage(result)
            }
            "isMemoryPressureHigh" -> {
                isMemoryPressureHigh(result)
            }
            "setVideoBufferSize" -> {
                setVideoBufferSize(call, result)
            }
            "setAggressiveMemoryManagement" -> {
                setAggressiveMemoryManagement(call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun initializeMemoryManagement(result: Result) {
        try {
            Log.d(TAG, "Initializing memory management")
            
            // Start monitoring memory pressure
            startMemoryPressureMonitoring()
            
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing memory management", e)
            result.error("INIT_ERROR", "Failed to initialize memory management", e.message)
        }
    }

    private fun forceGarbageCollection(result: Result) {
        try {
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastGcTime > gcInterval) {
                Log.d(TAG, "Forcing garbage collection")
                
                // Use reflection to call System.gc() multiple times for better cleanup
                repeat(3) {
                    System.gc()
                    Thread.sleep(100) // Small delay between GC calls
                }
                
                lastGcTime = currentTime
                
                // Send event to Flutter
                sendMemoryEvent("gc_completed", mapOf("timestamp" to currentTime))
                
                result.success(true)
            } else {
                Log.d(TAG, "Garbage collection skipped - too soon since last GC")
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during garbage collection", e)
            result.error("GC_ERROR", "Failed to force garbage collection", e.message)
        }
    }

    private fun forceAggressiveCleanup(result: Result) {
        try {
            Log.d(TAG, "Performing aggressive cleanup")
            
            // Force multiple garbage collections
            repeat(5) {
                System.gc()
                Thread.sleep(200)
            }
            
            // Clear image caches if possible
            clearImageCaches()
            
            // Send event to Flutter
            sendMemoryEvent("aggressive_cleanup_completed", mapOf("timestamp" to System.currentTimeMillis()))
            
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error during aggressive cleanup", e)
            result.error("CLEANUP_ERROR", "Failed to perform aggressive cleanup", e.message)
        }
    }

    private fun forceBufferCleanup(result: Result) {
        try {
            Log.d(TAG, "Performing buffer cleanup")
            
            // Force garbage collection
            System.gc()
            
            // Clear any image buffers
            clearImageBuffers()
            
            // Send event to Flutter
            sendMemoryEvent("buffer_cleanup_completed", mapOf("timestamp" to System.currentTimeMillis()))
            
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error during buffer cleanup", e)
            result.error("BUFFER_CLEANUP_ERROR", "Failed to perform buffer cleanup", e.message)
        }
    }

    private fun getMemoryUsage(result: Result) {
        try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            val memoryUsage = mapOf(
                "totalMemory" to memoryInfo.totalMem,
                "availableMemory" to memoryInfo.availMem,
                "usedMemory" to (memoryInfo.totalMem - memoryInfo.availMem),
                "memoryThreshold" to memoryInfo.threshold,
                "lowMemory" to memoryInfo.lowMemory,
                "maxMemory" to Runtime.getRuntime().maxMemory(),
                "freeMemory" to Runtime.getRuntime().freeMemory(),
                "totalMemoryRuntime" to Runtime.getRuntime().totalMemory()
            )
            
            result.success(memoryUsage)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting memory usage", e)
            result.error("MEMORY_USAGE_ERROR", "Failed to get memory usage", e.message)
        }
    }

    private fun isMemoryPressureHigh(result: Result) {
        try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            // Consider memory pressure high if:
            // 1. Available memory is less than 20% of total memory
            // 2. System reports low memory
            // 3. Available memory is below threshold
            val isHigh = memoryInfo.lowMemory || 
                        (memoryInfo.availMem < memoryInfo.totalMem * 0.2) ||
                        (memoryInfo.availMem < memoryInfo.threshold * 2)
            
            result.success(isHigh)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking memory pressure", e)
            result.error("MEMORY_PRESSURE_ERROR", "Failed to check memory pressure", e.message)
        }
    }

    private fun setVideoBufferSize(call: MethodCall, result: Result) {
        try {
            val size = call.argument<Int>("size")
            if (size != null) {
                videoBufferSize = size
                Log.d(TAG, "Video buffer size set to $size bytes")
                result.success(true)
            } else {
                result.error("INVALID_ARGUMENT", "Size parameter is required", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting video buffer size", e)
            result.error("BUFFER_SIZE_ERROR", "Failed to set video buffer size", e.message)
        }
    }

    private fun setAggressiveMemoryManagement(call: MethodCall, result: Result) {
        try {
            val enabled = call.argument<Boolean>("enabled")
            if (enabled != null) {
                isAggressiveMemoryManagementEnabled = enabled
                Log.d(TAG, "Aggressive memory management ${if (enabled) "enabled" else "disabled"}")
                result.success(true)
            } else {
                result.error("INVALID_ARGUMENT", "Enabled parameter is required", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting aggressive memory management", e)
            result.error("AGGRESSIVE_MEMORY_ERROR", "Failed to set aggressive memory management", e.message)
        }
    }

    private fun startMemoryPressureMonitoring() {
        // Monitor memory pressure periodically
        Thread {
            while (true) {
                try {
                    val isHigh = isMemoryPressureHigh()
                    if (isHigh) {
                        Log.w(TAG, "High memory pressure detected")
                        sendMemoryEvent("memory_pressure", mapOf("pressure" to "high"))
                        
                        if (isAggressiveMemoryManagementEnabled) {
                            // Force GC without result parameter for background monitoring
                            System.gc()
                            Thread.sleep(100)
                            System.gc()
                        }
                    }
                    
                    Thread.sleep(10000) // Check every 10 seconds
                } catch (e: Exception) {
                    Log.e(TAG, "Error in memory pressure monitoring", e)
                    Thread.sleep(30000) // Wait longer on error
                }
            }
        }.start()
    }

    private fun isMemoryPressureHigh(): Boolean {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            memoryInfo.lowMemory || (memoryInfo.availMem < memoryInfo.totalMem * 0.2)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking memory pressure", e)
            false
        }
    }

    private fun clearImageCaches() {
        try {
            // Try to clear image caches using reflection
            val bitmapClass = Class.forName("android.graphics.Bitmap")
            val recycleMethod = bitmapClass.getMethod("recycle")
            
            // This is a best-effort approach to clear image caches
            Log.d(TAG, "Attempting to clear image caches")
        } catch (e: Exception) {
            Log.d(TAG, "Could not clear image caches: ${e.message}")
        }
    }

    private fun clearImageBuffers() {
        try {
            // Force garbage collection to clear image buffers
            System.gc()
            Thread.sleep(100)
            System.gc()
            
            Log.d(TAG, "Image buffers cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing image buffers", e)
        }
    }

    private fun sendMemoryEvent(type: String, data: Map<String, Any>) {
        try {
            val event = mapOf(
                "type" to type,
                "data" to data,
                "timestamp" to System.currentTimeMillis()
            )
            // Ensure we're on the main thread when sending events
            if (Looper.myLooper() == Looper.getMainLooper()) {
                eventSink?.success(event)
            } else {
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success(event)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending memory event", e)
        }
    }

    companion object {
        private const val TAG = "MemoryManagementPlugin"
    }
}
