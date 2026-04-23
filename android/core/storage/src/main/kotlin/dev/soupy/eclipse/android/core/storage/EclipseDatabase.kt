package dev.soupy.eclipse.android.core.storage

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        ServiceEntity::class,
        StremioAddonEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class EclipseDatabase : RoomDatabase() {
    abstract fun serviceDao(): ServiceDao
    abstract fun stremioAddonDao(): StremioAddonDao

    companion object {
        fun build(context: Context): EclipseDatabase = Room.databaseBuilder(
            context,
            EclipseDatabase::class.java,
            "eclipse.db",
        ).build()
    }
}


