package dev.soupy.eclipse.android.core.storage

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface StremioAddonDao {
    @Query("SELECT * FROM stremio_addons ORDER BY sortIndex ASC, name ASC")
    fun observeAll(): Flow<List<StremioAddonEntity>>

    @Upsert
    suspend fun upsert(addons: List<StremioAddonEntity>)

    @Upsert
    suspend fun upsert(addon: StremioAddonEntity)

    @Delete
    suspend fun delete(addon: StremioAddonEntity)
}


