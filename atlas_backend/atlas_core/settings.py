# First, add this at the top of settings.py
import dj_database_url

# Then, update the DATABASES setting
DATABASES = {
    'default': dj_database_url.config(
        default='postgresql://postgres:atlas_deg1402@db.ycsafjkouarqpzanxelz.supabase.co:5432/postgres',
        conn_max_age=600,
    )
}