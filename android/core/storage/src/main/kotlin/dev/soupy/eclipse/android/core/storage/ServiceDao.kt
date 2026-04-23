package dev.soupy.eclipse.android.core.storage

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface ServiceDao {
    @Query("SELECT * FROM services ORDER BY sortIndex ASC, name ASC")
    fun observeAll(): Flow<List<ServiceEntity>>

    @Upsert
    suspend fun upsert(services: List<ServiceEntity>)

    @Upsert
    suspend fun upsert(service: ServiceEntity)

    @Delete
    suspend fun delete(service: ServiceEntity)
}


