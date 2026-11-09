import plotly.express as px
import pandas as pd
from croniter import croniter
from datetime import datetime, timedelta

# Sample cron schedules and durations (replace with your actual cron expressions and durations)
cron_schedule_durations = [
    {"schedule": "0 0 */7 * *", "duration_minutes": 120},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 1 */2 * *", "duration_minutes": 420},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 2 */7 * *", "duration_minutes": 520},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 3 */3 * *", "duration_minutes": 620},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 12 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 14 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "59 2 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "40 3 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "33 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 */7 * *", "duration_minutes": 240},   # Monthly on the 1st at midnight, duration 24 hours
     {"schedule": "0 0 */7 * *", "duration_minutes": 120},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 1 */2 * *", "duration_minutes": 420},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 2 */7 * *", "duration_minutes": 520},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 3 */3 * *", "duration_minutes": 620},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 12 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 14 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "59 2 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "40 3 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "33 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 */7 * *", "duration_minutes": 240},   # Monthly on the 1st at midnight, duration 24 hours
     {"schedule": "0 0 */7 * *", "duration_minutes": 120},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 1 */2 * *", "duration_minutes": 420},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 2 */7 * *", "duration_minutes": 520},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 3 */3 * *", "duration_minutes": 620},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 12 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 14 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "59 2 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "40 3 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "33 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 */7 * *", "duration_minutes": 240},   # Monthly on the 1st at midnight, duration 24 hours
     {"schedule": "0 0 */7 * *", "duration_minutes": 120},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 1 */2 * *", "duration_minutes": 420},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 2 */7 * *", "duration_minutes": 520},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 3 */3 * *", "duration_minutes": 620},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 12 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 14 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "59 2 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "40 3 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "33 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 */7 * *", "duration_minutes": 240},   # Monthly on the 1st at midnight, duration 24 hours
     {"schedule": "0 0 */7 * *", "duration_minutes": 120},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 1 */2 * *", "duration_minutes": 420},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 2 */7 * *", "duration_minutes": 520},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 3 */3 * *", "duration_minutes": 620},   # Every 5 minutes, duration 10 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 12 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 14 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "59 2 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "40 3 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "33 4 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 23 *   * *", "duration_minutes": 120},   # Daily at 3:00 AM, duration 60 minutes
    {"schedule": "0 5 */7 * *", "duration_minutes": 240}   # Monthly on the 1st at midnight, duration 24 hours
    # Add more cron expressions and durations as needed
]

# Create a DataFrame to store the schedule information
df = pd.DataFrame(columns=['Job', 'Start Time', 'End Time', 'Duration'])

# Function to generate schedule times and durations for visualization
def generate_schedule(cron_schedule, num_points=11):
    now = datetime.now()
    cron = croniter(cron_schedule['schedule'], now)
    start_times = [cron.get_next(datetime) for _ in range(num_points)]
    end_times = [start_time + timedelta(minutes=cron_schedule['duration_minutes']) for start_time in start_times]
    return start_times, end_times

# Populate the DataFrame with job names, start times, end times, and durations
for i, cron_schedule in enumerate(cron_schedule_durations):
    print (i)
    job_name = f"Job {i + 1}"
    start_times, end_times = generate_schedule(cron_schedule)
    #durations = [cron_schedule['duration_minutes']] * len(start_times)
    durations = cron_schedule['duration_minutes'] 
    df = pd.concat([df, pd.DataFrame({'Job': job_name,
                                      'Start Time': start_times,
                                      'End Time': end_times,
                                      'Duration': durations})])

# Assign a unique color to each job
colors = px.colors.qualitative.Set1[:len(cron_schedule_durations)]
colors = px.colors.qualitative.Set1 * 20
color_dict = {job: color for job, color in zip(df['Job'].unique(), colors)}
df['Color'] = df['Job'].map(color_dict)

# Filter the DataFrame based 
# on the desired time range (replace with your preferred range)
#start_date = datetime(2023, 7, 12)
#end_date   = datetime(2023, 7, 12)
# Set the time range for one month
start_date = datetime.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
end_date = start_date + pd.DateOffset(months=1) - pd.DateOffset(seconds=1)

# Filter the DataFrame based on the desired time range
filtered_df = df[(df['Start Time'] >= start_date) & (df['End Time'] <= end_date)]

# Create the plot
fig = px.timeline(filtered_df, x_start="Start Time", x_end="End Time", y="Job", color="Color",
                  labels={"Color": "Job"}, title="Cron Job Schedule Visualization with Durations")

fig.update_traces(marker_line_width=1, marker_line_color="black")  # Add black borders around rectangles
fig.update_layout(
    showlegend=False,  # Hide legend for better visibility
    xaxis_title="Time",
    yaxis_title="Job",
    plot_bgcolor='white',  # Set background color
    font=dict(family="Arial", size=12, color="black"),  # Customize font style
    margin=dict(l=50, r=50, b=50, t=80, pad=2),  # Adjust margins
)

fig.write_html("c:/Users/viktor/open-dve/open-dve/odve/script/schedule/cron_schedule_visualization.html")
# Show the plot
#fig.show()