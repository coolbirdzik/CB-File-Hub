package com.cbv.filehub

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

/**
 * Android storage volume inventory + best-effort eject/rename for the drive manager.
 *
 * Channel: cb_file_manager/storage_volumes
 */
class StorageVolumesPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "listVolumes" -> {
                try {
                    result.success(listVolumes())
                } catch (e: Exception) {
                    Log.e(TAG, "listVolumes failed", e)
                    result.error("LIST_FAILED", e.message, null)
                }
            }
            "ejectVolume" -> {
                val path = call.argument<String>("path") ?: ""
                val uuid = call.argument<String>("uuid")
                try {
                    result.success(ejectVolume(path, uuid))
                } catch (e: Exception) {
                    Log.e(TAG, "ejectVolume failed", e)
                    result.error("EJECT_FAILED", e.message, null)
                }
            }
            "renameVolume" -> {
                val path = call.argument<String>("path") ?: ""
                val label = call.argument<String>("label") ?: ""
                val uuid = call.argument<String>("uuid")
                try {
                    result.success(renameVolume(path, label, uuid))
                } catch (e: Exception) {
                    Log.e(TAG, "renameVolume failed", e)
                    result.error("RENAME_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun listVolumes(): List<Map<String, Any?>> {
        val sm = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        val rows = ArrayList<Map<String, Any?>>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            for (volume in sm.storageVolumes) {
                val dir = volumeDirectory(volume) ?: continue
                val path = dir.absolutePath
                val isPrimary = volume.isPrimary
                val isRemovable = volume.isRemovable
                val space = readSpace(path)
                val label = volume.getDescription(context) ?: ""
                val uuid = volume.uuid
                rows.add(
                    mapOf(
                        "path" to path,
                        "label" to label,
                        "uuid" to uuid,
                        "description" to label,
                        "isPrimary" to isPrimary,
                        "isRemovable" to isRemovable,
                        "canEject" to (isRemovable && !isPrimary),
                        "totalBytes" to space.first,
                        "freeBytes" to space.second,
                        "filesystem" to "",
                    ),
                )
            }
        }

        if (rows.isEmpty()) {
            // Pre-N / empty StorageManager fallback.
            val primary = Environment.getExternalStorageDirectory()
            if (primary != null && primary.exists()) {
                val space = readSpace(primary.absolutePath)
                rows.add(
                    mapOf(
                        "path" to primary.absolutePath,
                        "label" to "Internal storage",
                        "uuid" to null,
                        "description" to "Internal storage",
                        "isPrimary" to true,
                        "isRemovable" to false,
                        "canEject" to false,
                        "totalBytes" to space.first,
                        "freeBytes" to space.second,
                        "filesystem" to "",
                    ),
                )
            }
        }

        return rows
    }

    private fun volumeDirectory(volume: StorageVolume): File? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                volume.directory
            } else {
                @Suppress("DEPRECATION")
                val method = StorageVolume::class.java.getMethod("getPathFile")
                method.invoke(volume) as? File
            }
        } catch (e: Exception) {
            Log.w(TAG, "volumeDirectory failed", e)
            null
        }
    }

    private fun readSpace(path: String): Pair<Long, Long> {
        return try {
            val stat = StatFs(path)
            val total = stat.blockCountLong * stat.blockSizeLong
            val free = stat.availableBlocksLong * stat.blockSizeLong
            Pair(total, free)
        } catch (_: Exception) {
            Pair(0L, 0L)
        }
    }

    private fun ejectVolume(path: String, uuid: String?): Boolean {
        if (path.isBlank()) return false
        val sm = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        val volume = findVolume(sm, path, uuid) ?: return false
        if (volume.isPrimary) return false
        if (!volume.isRemovable) return false

        // Best-effort hidden unmount (may fail without system permission).
        if (!uuid.isNullOrBlank()) {
            try {
                val unmount = StorageManager::class.java.getMethod("unmount", String::class.java)
                unmount.invoke(sm, uuid)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "StorageManager.unmount unavailable: ${e.message}")
            }
        }

        // Open system storage settings so the user can eject safely.
        return try {
            val intent = Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open storage settings", e)
            false
        }
    }

    private fun renameVolume(path: String, label: String, uuid: String?): Boolean {
        if (path.isBlank() || label.isBlank()) return false
        // Third-party apps generally cannot rename volumes; open storage settings.
        return try {
            val intent = Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open storage settings for rename", e)
            false
        }
    }

    private fun findVolume(sm: StorageManager, path: String, uuid: String?): StorageVolume? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        val normalized = path.trimEnd('/')
        for (volume in sm.storageVolumes) {
            if (!uuid.isNullOrBlank() && volume.uuid == uuid) return volume
            val dir = volumeDirectory(volume) ?: continue
            val volPath = dir.absolutePath.trimEnd('/')
            if (volPath.equals(normalized, ignoreCase = true)) return volume
        }
        return null
    }

    companion object {
        private const val CHANNEL = "cb_file_manager/storage_volumes"
        private const val TAG = "StorageVolumesPlugin"
    }
}
