package dev.soupy.eclipse.android.core.storage

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "stremio_addons")
data class StremioAddonEntity(
    @PrimaryKey val transportUrl: String,
    val manifestId: String,
    val name: String,
    val enabled: Boolean = true,
    val sortIndex: Int = 0,
    val configured: Boolean = false,
    val manifestJson: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)


