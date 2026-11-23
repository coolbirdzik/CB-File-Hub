package com.coolbird.mobile_smb_native

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import android.content.Context
import android.view.Surface
import android.util.Log
import java.util.Properties
import java.io.InputStream
import java.io.ByteArrayOutputStream
import jcifs.context.SingletonContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay

/** MobileSmbNativePlugin */
class MobileSmbNativePlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var binding: FlutterPlugin.FlutterPluginBinding
  private lateinit var playbackChannel: SmbPlaybackChannel
  private var smbFile: SmbFile? = null
  private var isConnected = false
  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private val eventChannels = mutableMapOf<String, EventChannel>()
  private val eventSinks = mutableMapOf<String, EventSink>()
  
  // Buffer pool for streaming optimization
  private val bufferPool = mutableListOf<ByteArray>()
  private val bufferPoolSize = 3 // Tăng lên 3 buffers để cải thiện hiệu suất
  private val maxBufferSize = 1024 * 1024 // Tăng lên 1MB max buffer size
  
  // Memory management
  private val maxMemoryUsage = 100 * 1024 * 1024 // Tăng lên 100MB limit để tránh dừng stream
  private var currentMemoryUsage = 0L
  private var totalBytesRead = 0L
  private var lastLogTime = System.currentTimeMillis()
  private var lastLogBytes = 0L
  
  // Adaptive streaming control
  private var adaptiveChunkSize = 128 * 1024 // Tăng lên 128KB để cải thiện hiệu suất
  private var consecutiveMemoryWarnings = 0
  private var lastGcTime = 0L
  private val gcInterval = 2000L // Tăng lên 2 seconds between GC calls
  private val logTag = "SMB_DEBUG"
  private var logEnabled = false

  private fun logDebug(message: String) {
    if (logEnabled) {
      Log.d(logTag, message)
    }
  }

  private fun logWarn(message: String, throwable: Throwable? = null) {
    if (!logEnabled) return
    if (throwable != null) {
      Log.w(logTag, message, throwable)
    } else {
      Log.w(logTag, message)
    }
  }

  private fun logError(message: String, throwable: Throwable? = null) {
    if (!logEnabled) return
    if (throwable != null) {
      Log.e(logTag, message, throwable)
    } else {
      Log.e(logTag, message)
    }
  }

  private fun normalizePath(rawPath: String): String {
    var clean = rawPath.trim()
    if (clean.startsWith("/")) {
      clean = clean.substring(1)
    }
    if (clean.isEmpty()) {
      return clean
    }
    val share = smbFile?.share ?: ""
    if (share.isNotEmpty()) {
      if (clean == share) {
        return ""
      }
      if (clean.startsWith("$share/")) {
        clean = clean.substring(share.length + 1)
      }
    }
    return clean
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    binding = flutterPluginBinding
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "mobile_smb_native")
    channel.setMethodCallHandler(this)
    
    // Initialize JCIFS configuration
    initializeJcifs()
    playbackChannel = SmbPlaybackChannel(flutterPluginBinding.binaryMessenger)

    // VLC platform view registration removed - now using flutter_vlc_player
  }

  private fun initializeJcifs() {
    try {
      val props = Properties()
      props.setProperty("jcifs.smb.client.minVersion", "SMB202")
      props.setProperty("jcifs.smb.client.maxVersion", "SMB311")
      props.setProperty("jcifs.smb.client.responseTimeout", "120000")  // Increased to 120s for large image streaming
      props.setProperty("jcifs.smb.client.soTimeout", "180000")      // Increased to 180s
      props.setProperty("jcifs.smb.client.connTimeout", "30000")     // Increased to 30s
      
      SingletonContext.init(props)
    } catch (e: Exception) {
      // Ignore if already initialized
    }
  }
  
  // Buffer pool management methods
  private fun getBuffer(size: Int): ByteArray {
    synchronized(bufferPool) {
      // Try to find a buffer of the right size
      val index = bufferPool.indexOfFirst { it.size >= size }
      if (index != -1) {
        val buffer = bufferPool.removeAt(index)
        // If buffer is too large, trim it
        return if (buffer.size > size) {
          ByteArray(size).also { System.arraycopy(buffer, 0, it, 0, size) }
        } else {
          buffer
        }
      }
    }
    // Create new buffer if none available
    return ByteArray(size)
  }
  
  private fun returnBuffer(buffer: ByteArray) {
    synchronized(bufferPool) {
      if (bufferPool.size < bufferPoolSize && buffer.size <= maxBufferSize) {
        bufferPool.add(buffer)
      }
    }
  }
  
  // Memory management methods
  private fun canAllocate(size: Int): Boolean {
    return currentMemoryUsage + size <= maxMemoryUsage
  }
  
  private fun trackAllocation(size: Int) {
    currentMemoryUsage += size
  }
  
  private fun trackDeallocation(size: Int) {
    currentMemoryUsage -= size
  }
  
  private fun shouldForceGc(): Boolean {
    val currentTime = System.currentTimeMillis()
    return currentTime - lastGcTime > gcInterval
  }
  
  private fun performAdaptiveGc() {
    val currentTime = System.currentTimeMillis()
    if (currentTime - lastGcTime > gcInterval) {
      logDebug("performAdaptiveGc: Forcing GC after ${gcInterval}ms")
      System.gc()
      lastGcTime = currentTime
      consecutiveMemoryWarnings = 0
    }
  }
  
  private fun adjustChunkSize() {
    if (consecutiveMemoryWarnings > 3) {
      // Reduce chunk size cautiously when repeated memory pressure occurs
      adaptiveChunkSize = maxOf(64 * 1024, adaptiveChunkSize / 2) // Minimum 64KB
      logDebug("adjustChunkSize: Reduced to \${adaptiveChunkSize / 1024}KB after sustained memory warnings")
      consecutiveMemoryWarnings = 0
    } else if (consecutiveMemoryWarnings == 0 && currentMemoryUsage < maxMemoryUsage / 4) {
      // Increase chunk size if memory usage is very low
      adaptiveChunkSize = minOf(512 * 1024, adaptiveChunkSize * 2) // Maximum 512KB
      logDebug("adjustChunkSize: Increased to ${adaptiveChunkSize / 1024}KB due to low memory usage")
    }
  }
  
  private fun logMemoryStats() {
    val runtime = Runtime.getRuntime()
    val usedMemory = runtime.totalMemory() - runtime.freeMemory()
    val maxMemory = runtime.maxMemory()
    
    logDebug("Memory Stats: Used=${usedMemory/1024/1024}MB, Max=${maxMemory/1024/1024}MB")
    logDebug("Buffer Pool: Size=${bufferPool.size}, MaxSize=$bufferPoolSize")
    logDebug("Current Memory Usage: ${currentMemoryUsage/1024/1024}MB")
    logDebug("Adaptive Chunk Size: ${adaptiveChunkSize/1024}KB")
    logDebug("Consecutive Memory Warnings: $consecutiveMemoryWarnings")
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "connect" -> {
        scope.launch {
          try {
            val success = connect(call.arguments as Map<String, Any>)
            withContext(Dispatchers.Main) {
              result.success(success)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("CONNECT_ERROR", e.message, null)
            }
          }
        }
      }
      "disconnect" -> {
        scope.launch {
          try {
            val success = disconnect()
            withContext(Dispatchers.Main) {
              result.success(success)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("DISCONNECT_ERROR", e.message, null)
            }
          }
        }
      }
      "listShares" -> {
        scope.launch {
          try {
            val shares = listShares()
            withContext(Dispatchers.Main) {
              result.success(shares)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("LIST_SHARES_ERROR", e.message, null)
            }
          }
        }
      }
      "listDirectory" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val files = listDirectory(path)
            withContext(Dispatchers.Main) {
              result.success(files)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("LIST_DIRECTORY_ERROR", e.message, null)
            }
          }
        }
      }
      "readFile" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val data = readFile(path)
            withContext(Dispatchers.Main) {
              result.success(data)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("READ_FILE_ERROR", e.message, null)
            }
          }
        }
      }
      "writeFile" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val data = call.argument<ByteArray>("data") ?: ByteArray(0)
            val success = writeFile(path, data)
            withContext(Dispatchers.Main) {
              result.success(success)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("WRITE_FILE_ERROR", e.message, null)
            }
          }
        }
      }
      "delete" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val success = delete(path)
            withContext(Dispatchers.Main) {
              result.success(success)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("DELETE_ERROR", e.message, null)
            }
          }
        }
      }
      "createDirectory" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val success = createDirectory(path)
            withContext(Dispatchers.Main) {
              result.success(success)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("CREATE_DIRECTORY_ERROR", e.message, null)
            }
          }
        }
      }
      "isConnected" -> {
        result.success(isConnected)
      }
      "getFileInfo" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val fileInfo = getFileInfo(path)
            withContext(Dispatchers.Main) {
              result.success(fileInfo)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("GET_FILE_INFO_ERROR", e.message, null)
            }
          }
        }
      }
      "startFileStream" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            startFileStream(path)
            withContext(Dispatchers.Main) {
              result.success(true)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("START_FILE_STREAM_ERROR", e.message, null)
            }
          }
        }
      }
      "getSmbVersion" -> {
        scope.launch {
          try {
            val version = getSmbVersion()
            withContext(Dispatchers.Main) {
              result.success(version)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("GET_SMB_VERSION_ERROR", e.message, null)
            }
          }
        }
      }
      "getConnectionInfo" -> {
        scope.launch {
          try {
            val info = getConnectionInfo()
            withContext(Dispatchers.Main) {
              result.success(info)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("GET_CONNECTION_INFO_ERROR", e.message, null)
            }
          }
        }
      }
      "startOptimizedFileStream" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val chunkSize = call.argument<Int>("chunkSize") ?: 1024 * 1024
            startOptimizedFileStream(path, chunkSize)
            withContext(Dispatchers.Main) {
              result.success(true)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("START_OPTIMIZED_FILE_STREAM_ERROR", e.message, null)
            }
          }
        }
      }
      "seekFileStream" -> {
        scope.launch {
          try {
            val path = call.argument<String>("path") ?: ""
            val offset = (call.argument<Number>("offset") ?: 0).toLong()
            val chunkSize = call.argument<Int>("chunkSize") ?: 1024 * 1024
            seekFileStream(path, offset, chunkSize)
            withContext(Dispatchers.Main) {
              result.success(true)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("SEEK_FILE_STREAM_ERROR", e.message, null)
            }
          }
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private suspend fun connect(config: Map<String, Any>): Boolean = withContext(Dispatchers.IO) {
    try {
      val host = config["host"] as String
      val port = config["port"] as? Int ?: 445
      val username = config["username"] as String
      val password = config["password"] as String
      val domain = config["domain"] as? String
      val shareName = config["shareName"] as? String
      
      logDebug("connect: Attempting to connect to $host:$port with user $username")
      logDebug("connect: Domain: $domain, ShareName: $shareName")
      
      val auth = if (domain != null) {
        NtlmPasswordAuthenticator(domain, username, password)
      } else {
        NtlmPasswordAuthenticator(username, password)
      }
      
      val context = SingletonContext.getInstance().withCredentials(auth)
      
      val url = if (shareName != null) {
        "smb://$host:$port/$shareName/"
      } else {
        "smb://$host:$port/"
      }
      
      logDebug("connect: Using URL: $url")
      
      smbFile = SmbFile(url, context)
      
      // Test connection by listing the directory
      logDebug("connect: Testing connection by listing files")
      val files = smbFile?.listFiles()
      logDebug("connect: Connection test successful, found ${files?.size ?: 0} files")
      
      isConnected = true
      true
    } catch (e: Exception) {
      logError("connect: Connection failed", e)
      isConnected = false
      false
    }
  }

  private suspend fun disconnect(): Boolean = withContext(Dispatchers.IO) {
    try {
      smbFile = null
      isConnected = false
      true
    } catch (e: Exception) {
      false
    }
  }

  private suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
    try {
      logDebug("listShares: Starting to list shares")
      if (smbFile == null) {
        logDebug("listShares: smbFile is null")
        return@withContext emptyList()
      }
      
      // Extract server info from current smbFile URL
      val currentUrl = smbFile!!.url.toString()
      logDebug("listShares: Current URL: $currentUrl")
      
      // Create server URL with proper format: smb://host:port/
      val serverUrl = if (currentUrl.contains("://")) {
        val parts = currentUrl.split("://")
        val protocol = parts[0]
        val hostPart = parts[1].split("/")[0] // Get host:port part
        "$protocol://$hostPart/"
      } else {
        "smb://${smbFile!!.server}/"
      }
      
      logDebug("listShares: Using server URL: $serverUrl")
      val serverFile = SmbFile(serverUrl, smbFile!!.context)
      
      val files = serverFile.listFiles()
      logDebug("listShares: Got ${files?.size ?: 0} files")
      
      val shares = files?.map { 
        val shareName = it.name.removeSuffix("/")
        logDebug("listShares: Found share: $shareName")
        shareName
      } ?: emptyList()
      
      logDebug("listShares: Returning ${shares.size} shares: $shares")
      return@withContext shares
    } catch (e: Exception) {
      logError("listShares: Exception occurred", e)
      emptyList()
    }
  }

  private suspend fun listDirectory(path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
    try {
      logDebug("listDirectory: Starting to list directory with path: '$path'")
      if (smbFile == null) {
        logDebug("listDirectory: smbFile is null")
        return@withContext emptyList()
      }
      
      logDebug("listDirectory: Base smbFile URL: ${smbFile!!.url}")
      logDebug("listDirectory: Base smbFile path: ${smbFile!!.path}")
      logDebug("listDirectory: Base smbFile context: ${smbFile!!.context}")
      
      val targetFile = if (path.isEmpty()) {
        logDebug("listDirectory: Using root smbFile")
        smbFile!!
      } else {
        // Check if base smbFile is server root (no share)
        val baseUrl = smbFile!!.url.toString()
        val isServerRoot = baseUrl.matches(Regex("smb://[^/]+:\\d+/?$"))
        
        if (isServerRoot && path.startsWith("/")) {
          // Path is likely a share name, create new SmbFile with full URL
          val shareName = path.removePrefix("/").removeSuffix("/")
          val host = smbFile!!.server
          val port = smbFile!!.url.port
          val newUrl = "smb://$host:$port/$shareName/"
          logDebug("listDirectory: Creating new SmbFile for share with URL: $newUrl")
          val newFile = SmbFile(newUrl, smbFile!!.context)
          logDebug("listDirectory: New file URL: ${newFile.url}")
          logDebug("listDirectory: New file share: ${newFile.share}")
          newFile
        } else {
          // Normal subdirectory path
          val directoryPath = if (path.endsWith("/")) path else "$path/"
          logDebug("listDirectory: Creating SmbFile with path: '$directoryPath'")
          val newFile = SmbFile(smbFile!!, directoryPath)
          logDebug("listDirectory: Target file path: ${newFile.path}")
          logDebug("listDirectory: Target file URL: ${newFile.url}")
          logDebug("listDirectory: Target file server: ${newFile.server}")
          logDebug("listDirectory: Target file share: ${newFile.share}")
          newFile
        }
      }
      
      logDebug("listDirectory: About to call listFiles() on: ${targetFile.url}")
      val files = targetFile.listFiles()
      logDebug("listDirectory: Got ${files?.size ?: 0} files")
      
      val result = files?.map { file ->
        logDebug("listDirectory: Processing file: ${file.name}, isDirectory: ${file.isDirectory}")
        mapOf<String, Any>(
          "name" to file.name.removeSuffix("/"),
          "path" to file.path,
          "isDirectory" to file.isDirectory,
          "size" to file.length(),
          "lastModified" to file.lastModified(),
          "isHidden" to file.isHidden,
          "permissions" to ""
        )
      } ?: emptyList()
      
      logDebug("listDirectory: Returning ${result.size} items")
      return@withContext result
    } catch (e: Exception) {
      logError("listDirectory: Exception occurred", e)
      logError("listDirectory: Exception type: ${e.javaClass.simpleName}")
      logError("listDirectory: Exception message: ${e.message}")
      logError("listDirectory: Exception cause: ${e.cause}")
      emptyList()
    }
  }

  private suspend fun readFile(path: String): ByteArray = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) {
        logError("readFile: SMB connection is null for path: $path")
        throw Exception("SMB connection is null")
      }
      
      logDebug("readFile: Original path received: $path")
      logDebug("readFile: Original path bytes: ${path.toByteArray().joinToString(",") { it.toString() }}")
      
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      logDebug("readFile: Decoded path: $decodedPath")
      logDebug("readFile: Decoded path bytes: ${decodedPath.toByteArray().joinToString(",") { it.toString() }}")
      val cleanPath = normalizePath(decodedPath)
      logDebug("readFile: Normalized path: $cleanPath")
      logDebug("readFile: Reading file at path: $cleanPath")

      val targetFile = SmbFile(smbFile!!, cleanPath)
      
      if (!targetFile.exists()) {
        logError("readFile: File does not exist: $decodedPath")
        throw Exception("File does not exist: $decodedPath")
      }
      
      if (targetFile.isDirectory) {
        logError("readFile: Path is a directory, not a file: $decodedPath")
        throw Exception("Path is a directory, not a file: $decodedPath")
      }
      
      val fileSize = targetFile.length()
      logDebug("readFile: File size: $fileSize bytes")
      
      val inputStream: InputStream = targetFile.inputStream
      val outputStream = ByteArrayOutputStream()
      
      inputStream.use { input ->
        outputStream.use { output ->
          input.copyTo(output)
        }
      }
      
      val result = outputStream.toByteArray()
      logDebug("readFile: Successfully read ${result.size} bytes")
      
      if (result.isEmpty()) {
        logWarn("readFile: Read 0 bytes from file: $decodedPath")
        throw Exception("Read 0 bytes from file: $decodedPath")
      }
      
      result
    } catch (e: Exception) {
      logError("readFile: Error reading file $path: ${e.message}", e)
      throw e
    }
  }

  private suspend fun writeFile(path: String, data: ByteArray): Boolean = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) return@withContext false
      
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      val targetFile = SmbFile(smbFile!!, decodedPath)
      targetFile.outputStream.use { output ->
        output.write(data)
      }
      true
    } catch (e: Exception) {
      false
    }
  }

  private suspend fun delete(path: String): Boolean = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) return@withContext false
      
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      val targetFile = SmbFile(smbFile!!, decodedPath)
      targetFile.delete()
      true
    } catch (e: Exception) {
      false
    }
  }

  private suspend fun createDirectory(path: String): Boolean = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) return@withContext false
      
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      val targetFile = SmbFile(smbFile!!, decodedPath)
      targetFile.mkdirs()
      true
    } catch (e: Exception) {
      false
    }
  }

  private suspend fun getFileInfo(path: String): Map<String, Any>? = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) return@withContext null
      
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      val cleanPath = normalizePath(decodedPath)
      val targetFile = SmbFile(smbFile!!, cleanPath)
      if (!targetFile.exists()) return@withContext null
      
      mapOf<String, Any>(
        "name" to targetFile.name.removeSuffix("/"),
        "path" to targetFile.path,
        "isDirectory" to targetFile.isDirectory,
        "size" to targetFile.length(),
        "lastModified" to targetFile.lastModified(),
        "isHidden" to targetFile.isHidden,
        "permissions" to ""
      )
    } catch (e: Exception) {
      null
    }
  }

  private suspend fun startFileStream(path: String) = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) {
        logError("startFileStream: smbFile is null")
        return@withContext
      }
      
      // Decode URL-encoded path
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      logDebug("startFileStream: Original path: $path")
      logDebug("startFileStream: Decoded path: $decodedPath")
      logDebug("startFileStream: Base smbFile URL: ${smbFile!!.url}")
      
      // Create target file with proper path handling
      val targetFile = try {
        val cleanPath = normalizePath(decodedPath)
        logDebug("startFileStream: Normalized path: $cleanPath")
        
        val file = SmbFile(smbFile!!, cleanPath)
        logDebug("startFileStream: Target file URL: ${file.url}")
        logDebug("startFileStream: Target file path: ${file.path}")
        file
      } catch (e: Exception) {
        logError("startFileStream: Error creating SmbFile", e)
        throw e
      }
      
      // Check if file exists
      if (!targetFile.exists()) {
        logError("startFileStream: File does not exist: ${targetFile.url}")
        return@withContext
      }
      
      if (targetFile.isDirectory) {
        logError("startFileStream: Path is directory, not file: ${targetFile.url}")
        return@withContext
      }
      
      logDebug("startFileStream: File exists and is valid, size: ${targetFile.length()}")
      
      // Create event channel for this file stream
      val sanitizedPath = path.replace(Regex("[^a-zA-Z0-9]"), "_")
      val channelName = "mobile_smb_native/stream_$sanitizedPath"
      logDebug("startFileStream: Creating event channel: $channelName")
      
      withContext(Dispatchers.Main) {
        // Remove existing channel if any
        eventChannels[path]?.setStreamHandler(null)
        
        val eventChannel = EventChannel(binding.binaryMessenger, channelName)
        eventChannels[path] = eventChannel
        
        eventChannel.setStreamHandler(object : StreamHandler {
          override fun onListen(arguments: Any?, events: EventSink?) {
            logDebug("startFileStream: EventChannel onListen called")
            events?.let { sink ->
              eventSinks[path] = sink
              // Start streaming in background
              scope.launch {
                streamFile(targetFile, sink)
              }
            }
          }
          
          override fun onCancel(arguments: Any?) {
            logDebug("startFileStream: EventChannel onCancel called")
            eventSinks.remove(path)
          }
        })
        
        logDebug("startFileStream: Event channel setup complete")
      }
    } catch (e: Exception) {
      logError("startFileStream: Exception occurred", e)
      logError("startFileStream: Exception type: ${e.javaClass.simpleName}")
      logError("startFileStream: Exception message: ${e.message}")
      throw e
    }
  }
  
  private suspend fun streamFile(targetFile: SmbFile, sink: EventSink) = withContext(Dispatchers.IO) {
    try {
      logDebug("streamFile: Starting to stream file: ${targetFile.url}")
      logDebug("streamFile: File size: ${targetFile.length()}")
      
      val inputStream = targetFile.inputStream
      val buffer = ByteArray(256 * 1024) // 256KB buffer to improve throughput and reduce memory pressure
      var totalBytesRead = 0L
      
      logDebug("streamFile: Input stream created successfully")
      
      inputStream.use { input ->
        var bytesRead: Int
        var chunkCount = 0
        
        while (input.read(buffer).also { bytesRead = it } != -1) {
          chunkCount++
          totalBytesRead += bytesRead
          
          val chunk = if (bytesRead == buffer.size) {
            buffer.copyOf()
          } else {
            buffer.copyOfRange(0, bytesRead)
          }
          
          if (chunkCount % 100 == 0) { // Log every 100 chunks
            logDebug("streamFile: Sent chunk $chunkCount, total bytes: $totalBytesRead")
          }
          
          withContext(Dispatchers.Main) {
            sink.success(chunk)
          }
        }
        
        logDebug("streamFile: Finished reading file, total chunks: $chunkCount, total bytes: $totalBytesRead")
      }
      
      // Signal end of stream
      withContext(Dispatchers.Main) {
        sink.endOfStream()
      }
      
      logDebug("streamFile: Stream completed successfully")
    } catch (e: Exception) {
      logError("streamFile: Exception occurred", e)
      logError("streamFile: Exception type: ${e.javaClass.simpleName}")
      logError("streamFile: Exception message: ${e.message}")
      logError("streamFile: Exception cause: ${e.cause}")
      
      withContext(Dispatchers.Main) {
        sink.error("STREAM_ERROR", e.message ?: "Unknown streaming error", e.toString())
      }
    }
  }

  private suspend fun getSmbVersion(): String = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) {
        return@withContext "Not connected"
      }
      
      // For jCIFS, we'll use a simplified approach since direct property access is limited
      // We'll return the configured max version from our initialization
      val actualVersion = "SMB3.1.1" // Based on our initialization in initializeJcifs()
      
      logDebug("getSmbVersion: Using configured version: $actualVersion")
      return@withContext actualVersion
    } catch (e: Exception) {
      logError("getSmbVersion: Exception occurred", e)
      return@withContext "Unknown"
    }
  }

  private suspend fun getConnectionInfo(): String = withContext(Dispatchers.IO) {
    try {
      if (smbFile == null) {
        return@withContext "Not connected"
      }
      
      val server = smbFile!!.server
      val share = smbFile!!.share
      val credentials = smbFile!!.context.credentials
      val username = credentials?.toString()?.split(":")?.firstOrNull() ?: "Unknown"
      val version = getSmbVersion()
      
      val info = "Server: $server, Share: $share, Version: $version, User: $username"
      logDebug("getConnectionInfo: $info")
      return@withContext info
    } catch (e: Exception) {
      logError("getConnectionInfo: Exception occurred", e)
      return@withContext "Connection info unavailable"
    }
  }

  private suspend fun startOptimizedFileStream(path: String, chunkSize: Int) = withContext(Dispatchers.IO) {
    try {
      logDebug("startOptimizedFileStream: Starting optimized stream for path: $path")
      logDebug("startOptimizedFileStream: Chunk size: $chunkSize bytes")
      
      if (smbFile == null) {
        throw Exception("Not connected to SMB server")
      }
      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      val cleanPath = normalizePath(decodedPath)
      val targetFile = if (cleanPath.isEmpty()) {
        smbFile!!
      } else {
        SmbFile(smbFile!!, cleanPath)
      }
      
      if (!targetFile.exists()) {
        throw Exception("File not found: $path")
      }
      
      logDebug("startOptimizedFileStream: Target file: ${targetFile.url}")
      logDebug("startOptimizedFileStream: File size: ${targetFile.length()}")
      
      // Create optimized event channel
      val sanitizedPath = path.replace(Regex("[^a-zA-Z0-9]"), "_")
      val channelName = "mobile_smb_native/optimized_stream_$sanitizedPath"
      
      withContext(Dispatchers.Main) {
        // Remove existing optimized channel if any
        eventChannels[path]?.setStreamHandler(null)
        
        val eventChannel = EventChannel(binding.binaryMessenger, channelName)
        eventChannels[path] = eventChannel
        
        eventChannel.setStreamHandler(object : StreamHandler {
          override fun onListen(arguments: Any?, events: EventSink?) {
            logDebug("startOptimizedFileStream: EventChannel onListen called")
            events?.let { sink ->
              eventSinks[path] = sink
              // Start optimized streaming in background
              scope.launch {
                streamFileOptimized(targetFile, sink, chunkSize)
              }
            }
          }
          
          override fun onCancel(arguments: Any?) {
            logDebug("startOptimizedFileStream: EventChannel onCancel called")
            eventSinks.remove(path)
          }
        })
        
        logDebug("startOptimizedFileStream: Optimized event channel setup complete")
      }
    } catch (e: Exception) {
      logError("startOptimizedFileStream: Exception occurred", e)
      logError("startOptimizedFileStream: Exception type: ${e.javaClass.simpleName}")
      logError("startOptimizedFileStream: Exception message: ${e.message}")
      throw e
    }
  }
  
  private suspend fun streamFileOptimized(
    targetFile: SmbFile,
    sink: EventSink,
    chunkSize: Int,
    startOffset: Long = 0L,
    maxBytes: Long? = null
  ) = withContext(Dispatchers.IO) {
    var inputStream: InputStream? = null
    var readBuffer: ByteArray? = null
    var chunkBuffer: ByteArray? = null
    
    try {
      logDebug("streamFileOptimized: Starting optimized stream for file: ${targetFile.url}")
      logDebug("streamFileOptimized: File size: ${targetFile.length()}")
      logDebug("streamFileOptimized: Start offset: $startOffset")
      logDebug("streamFileOptimized: Initial chunk size: $chunkSize bytes")
      logDebug("streamFileOptimized: Adaptive chunk size: ${adaptiveChunkSize} bytes")
      
      // Reset adaptive controls
      consecutiveMemoryWarnings = 0
      lastGcTime = System.currentTimeMillis()
      
      // Log initial memory stats
      logMemoryStats()
      
      inputStream = targetFile.inputStream
      
      // Skip to start offset if specified (for seek support)
      if (startOffset > 0) {
        logDebug("streamFileOptimized: Skipping to offset: $startOffset")
        val skipped = inputStream.skip(startOffset)
        logDebug("streamFileOptimized: Actually skipped: $skipped bytes")
        if (skipped != startOffset) {
          logWarn("streamFileOptimized: Could not skip full offset, expected: $startOffset, actual: $skipped")
        }
      }
      
      val baseChunkSize = minOf(adaptiveChunkSize, chunkSize)
      readBuffer = getBuffer(baseChunkSize)
      trackAllocation(baseChunkSize)
      
      var chunkCount = 0
      totalBytesRead = 0L
      lastLogTime = System.currentTimeMillis()
      lastLogBytes = 0L
      
      logDebug("streamFileOptimized: Input stream created successfully")
      
      var bytesRead: Int
      var bytesSent = 0L
      while (true) {
        val remaining = if (maxBytes != null) maxBytes - bytesSent else baseChunkSize.toLong()
        if (remaining <= 0) break
        val toRead = minOf(baseChunkSize.toLong(), remaining).toInt()
        bytesRead = inputStream.read(readBuffer, 0, toRead)
        if (bytesRead == -1) break
        chunkCount++
        totalBytesRead += bytesRead
        bytesSent += bytesRead
        
        // Check memory usage before allocating new buffer
        if (!canAllocate(bytesRead)) {
          consecutiveMemoryWarnings++
          logWarn("streamFileOptimized: Memory limit reached (warning #$consecutiveMemoryWarnings), waiting for GC")
          
          // Perform adaptive GC
          performAdaptiveGc()
          delay(200) // Wait longer for GC
          
          // Adjust chunk size if needed
          adjustChunkSize()
          
          if (!canAllocate(bytesRead)) {
            logError("streamFileOptimized: Cannot allocate memory for chunk after GC")
            break
          }
        } else {
          // Reset consecutive warnings if memory is OK
          if (consecutiveMemoryWarnings > 0) {
            consecutiveMemoryWarnings = 0
          }
        }
        
        // Create a slice to send without allocating separate pool buffer
        chunkBuffer = readBuffer.copyOfRange(0, bytesRead)
        
        // Log progress every 3 seconds or every 25MB (reduced frequency)
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastLogTime > 3000 || totalBytesRead - lastLogBytes > 25 * 1024 * 1024) {
          val speed = if (currentTime > lastLogTime) {
            val bytesDiff = totalBytesRead - lastLogBytes
            val timeDiff = (currentTime - lastLogTime) / 1000.0
            String.format("%.2f MB/s", (bytesDiff / 1024.0 / 1024.0) / timeDiff)
          } else "N/A"
          
          logDebug("streamFileOptimized: Progress - Chunks: $chunkCount, Total: ${totalBytesRead / 1024 / 1024}MB, Speed: $speed")
          logMemoryStats()
          lastLogTime = currentTime
          lastLogBytes = totalBytesRead
        }
        
        // Adaptive back-off only when sustained memory pressure
        val delayMs = if (consecutiveMemoryWarnings > 2) 50L else 0L
        if (delayMs > 0) {
          delay(delayMs)
        }
        
        // Gửi ByteArray trực tiếp lên Flutter
        withContext(Dispatchers.Main) {
          sink.success(chunkBuffer)
        }
        
        // Không cần trả buffer phụ vì copyOfRange tạo mảng mới nhỏ gọn
        chunkBuffer = null
        
        // Periodic adaptive GC - more frequent
        if (chunkCount % 20 == 0) {
          performAdaptiveGc()
        }
        if (maxBytes != null && bytesSent >= maxBytes) {
          break
        }
      }
      
      logDebug("streamFileOptimized: Finished reading file, total chunks: $chunkCount, total bytes: $totalBytesRead")
      
      // Signal end of stream
      withContext(Dispatchers.Main) {
        sink.endOfStream()
      }
      
      logDebug("streamFileOptimized: Optimized stream completed successfully")
    } catch (e: Exception) {
      logError("streamFileOptimized: Exception occurred", e)
      logError("streamFileOptimized: Exception type: ${e.javaClass.simpleName}")
      logError("streamFileOptimized: Exception message: ${e.message}")
      logError("streamFileOptimized: Exception cause: ${e.cause}")
      
      withContext(Dispatchers.Main) {
        sink.error("OPTIMIZED_STREAM_ERROR", e.message ?: "Unknown optimized streaming error", e.toString())
      }
    } finally {
      // Clean up resources
      try {
        inputStream?.close()
      } catch (e: Exception) {
        logWarn("streamFileOptimized: Error closing input stream", e)
      }
      
      // Return buffers to pool
      readBuffer?.let { 
        returnBuffer(it)
        trackDeallocation(it.size)
      }
      chunkBuffer?.let { 
        returnBuffer(it)
        trackDeallocation(it.size)
      }
      
      // Final memory stats
      logMemoryStats()
    }
  }

  private suspend fun seekFileStream(path: String, offset: Long, chunkSize: Int) = withContext(Dispatchers.IO) {
    try {
      logDebug("seekFileStream: Starting seek stream for path: $path")
      logDebug("seekFileStream: Seek offset: $offset bytes")
      logDebug("seekFileStream: Chunk size: $chunkSize bytes")
      
      if (!isConnected || smbFile == null) {
        logError("seekFileStream: Not connected to SMB server")
        throw Exception("Not connected to SMB server")
      }

      val decodedPath = java.net.URLDecoder.decode(path, "UTF-8")
      val cleanPath = normalizePath(decodedPath)
      if (cleanPath.isEmpty()) {
        throw Exception("Invalid file path")
      }
      val targetFile = SmbFile(smbFile!!, cleanPath)
      if (!targetFile.exists()) {
        logError("seekFileStream: File does not exist: $path")
        throw Exception("File does not exist: $path")
      }
      
      if (targetFile.isDirectory) {
        logError("seekFileStream: Path is a directory: $path")
        throw Exception("Path is a directory: $path")
      }
      
      logDebug("seekFileStream: Target file: ${targetFile.url}")
      logDebug("seekFileStream: File size: ${targetFile.length()}")
      
      // Validate offset
      if (offset < 0 || offset >= targetFile.length()) {
        logError("seekFileStream: Invalid offset: $offset, file size: ${targetFile.length()}")
        throw Exception("Invalid offset: $offset")
      }
      
      // Cancel existing stream if any
      val existingSink = eventSinks[path]
      if (existingSink != null) {
        withContext(Dispatchers.Main) {
          existingSink.endOfStream()
        }
        eventSinks.remove(path)
      }
      
      // Create new event channel for seek stream
      val sanitizedPath = path.replace(Regex("[^a-zA-Z0-9]"), "_")
      val eventChannelName = "mobile_smb_native/seek_stream_$sanitizedPath"

      withContext(Dispatchers.Main) {
        val eventChannel = EventChannel(binding.binaryMessenger, eventChannelName)
        eventChannel.setStreamHandler(object : StreamHandler {
          override fun onListen(arguments: Any?, events: EventSink?) {
            logDebug("seekFileStream: EventChannel onListen called")
            events?.let { sink ->
              eventSinks[path] = sink
              // Start optimized streaming with offset in background
              scope.launch {
                streamFileOptimized(targetFile, sink, chunkSize, offset, chunkSize.toLong())
              }
            }
          }

          override fun onCancel(arguments: Any?) {
            logDebug("seekFileStream: EventChannel onCancel called")
            eventSinks.remove(path)
          }
        })
      }

      logDebug("seekFileStream: Seek event channel setup complete")
    } catch (e: Exception) {
      logError("seekFileStream: Exception occurred", e)
      logError("seekFileStream: Exception type: ${e.javaClass.simpleName}")
      logError("seekFileStream: Exception message: ${e.message}")
      throw e
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    playbackChannel.detach()
    channel.setMethodCallHandler(null)
    // Clean up event channels
    eventChannels.values.forEach { it.setStreamHandler(null) }
    eventChannels.clear()
    eventSinks.clear()
    scope.cancel()
    
    // Clean up buffer pool
    synchronized(bufferPool) {
      bufferPool.clear()
    }
  }
}
