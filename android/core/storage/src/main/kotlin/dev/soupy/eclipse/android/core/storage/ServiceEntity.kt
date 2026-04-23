package dev.soupy.eclipse.android.core.storage

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "services")
data class ServiceEntity(
    @PrimaryKey val id: String,
    val name: String,
    val manifestUrl: String? = null,
    val scriptUrl: String? = null,
    val enabled: Boolean = true,
    val sortIndex: Int = 0,
    val sourceKind: String = "service",
    val configurationJson: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)


