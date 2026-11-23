package com.coolbird.mobile_smb_native

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.io.InputStream
import java.util.UUID
import jcifs.context.SingletonContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

internal class SmbPlaybackChannel(messenger: BinaryMessenger) {
  private val channel = MethodChannel(messenger, "mobile_smb_native/playback")
  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private val readers = mutableMapOf<String, Reader>()
  private var detached = false

  init {
    channel.setMethodCallHandler(::handle)
  }

  private fun handle(call: MethodCall, result: MethodChannel.Result) {
    scope.launch {
      try {
        when (call.method) {
          "open" -> result.success(open(call))
          "read" -> {
            val id = requireNotNull(call.argument<String>("id"))
            val offset = requireNotNull(call.argument<Number>("offset")).toLong()
            val length = requireNotNull(call.argument<Int>("length"))
            val reader = synchronized(readers) { readers[id] }
            result.success(checkNotNull(reader).read(offset, length))
          }
          "close" -> {
            val id = requireNotNull(call.argument<String>("id"))
            synchronized(readers) { readers.remove(id) }?.close()
            result.success(null)
          }
          else -> result.notImplemented()
        }
      } catch (e: FileNotFoundException) {
        result.error("SMB_PLAYBACK_NOT_FOUND", "Video not found", null)
      } catch (e: Exception) {
        result.error("SMB_PLAYBACK_ERROR", e.javaClass.simpleName, null)
      }
    }
  }

  private fun open(call: MethodCall): Map<String, Any> {
    val host = requireNotNull(call.argument<String>("host"))
    val port = call.argument<Int>("port") ?: 445
    val share = requireNotNull(call.argument<String>("shareName"))
    val path = requireNotNull(call.argument<String>("path"))
    if (path.isEmpty()) throw FileNotFoundException()

    val domain = call.argument<String>("domain")
    val username = call.argument<String>("username") ?: ""
    val password = call.argument<String>("password") ?: ""
    val auth = if (domain == null) NtlmPasswordAuthenticator(username, password)
    else NtlmPasswordAuthenticator(domain, username, password)
    val context = SingletonContext.getInstance().withCredentials(auth)
    val authority = if (host.contains(':')) "[$host]" else host
    val file = SmbFile("smb://$authority:$port/", context).use { server ->
      // Dart has already decoded the URL path. Pass the literal name to JCIFS.
      SmbFile(server, "$share/$path")
    }
    try {
      if (!file.isFile) throw FileNotFoundException()
      val size = file.length()
      val id = UUID.randomUUID().toString()
      synchronized(readers) {
        check(!detached)
        readers[id] = Reader(file, size)
      }
      return mapOf("id" to id, "size" to size)
    } catch (e: Exception) {
      file.close()
      throw e
    }
  }

  fun detach() {
    channel.setMethodCallHandler(null)
    val active = synchronized(readers) {
      detached = true
      readers.values.toList().also { readers.clear() }
    }
    scope.cancel()
    if (active.isNotEmpty()) {
      CoroutineScope(Dispatchers.IO).launch {
        active.forEach { runCatching { it.close() } }
      }
    }
  }

  private class Reader(private val file: SmbFile, private val size: Long) {
    private var input: InputStream? = null
    private var position = 0L
    private var closed = false

    @Synchronized
    fun read(offset: Long, length: Int): ByteArray {
      check(!closed)
      require(offset in position..size && length in 1..1024 * 1024)
      val count = minOf(length.toLong(), size - offset).toInt()
      if (count == 0) return ByteArray(0)
      val stream = input ?: file.inputStream.also { input = it }
      // JCIFS moves the file pointer without reading the skipped bytes.
      val skip = offset - position
      check(stream.skip(skip) == skip)
      position = offset

      val bytes = ByteArray(count)
      var bytesRead = 0
      while (bytesRead < count) {
        val read = stream.read(bytes, bytesRead, count - bytesRead)
        if (read <= 0) break
        bytesRead += read
        position += read
      }
      return if (bytesRead == count) bytes else bytes.copyOf(bytesRead)
    }

    @Synchronized
    fun close() {
      if (closed) return
      closed = true
      try {
        input?.close()
      } finally {
        file.close()
      }
    }
  }
}
