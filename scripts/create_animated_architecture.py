#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - Animated Architecture Diagram
Creates a professional animated GIF showing the complete infrastructure flow
"""

import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend for compatibility

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import Circle, FancyBboxPatch, FancyArrowPatch
import imageio
import math

# Color scheme - Professional dark theme
COLORS = {
    'bg': '#0d1117',
    'primary': '#58a6ff',
    'secondary': '#f85149', 
    'success': '#3fb950',
    'warning': '#d29922',
    'text': '#f0f6fc',
    'accent': '#bc8cff',
    'glow': '#7c3aed'
}

# Infrastructure components with positions
COMPONENTS = {
    # AWS Regions
    'us-east-1': {'pos': (0.25, 0.8), 'type': 'region', 'color': COLORS['primary']},
    'us-west-2': {'pos': (0.75, 0.8), 'type': 'region', 'color': COLORS['secondary']},
    
    # Core Infrastructure
    'ALB': {'pos': (0.25, 0.65), 'type': 'service', 'color': COLORS['success']},
    'Jenkins ASG': {'pos': (0.25, 0.5), 'type': 'service', 'color': COLORS['primary']},
    'EFS': {'pos': (0.25, 0.35), 'type': 'storage', 'color': COLORS['warning']},
    
    # Security & Automation
    'TFSec': {'pos': (0.1, 0.2), 'type': 'security', 'color': COLORS['accent']},
    'Trivy': {'pos': (0.25, 0.2), 'type': 'security', 'color': COLORS['accent']},
    'Checkov': {'pos': (0.4, 0.2), 'type': 'security', 'color': COLORS['accent']},
    
    # Packer & AMI
    'Packer': {'pos': (0.5, 0.65), 'type': 'automation', 'color': COLORS['success']},
    'Golden AMI': {'pos': (0.5, 0.5), 'type': 'automation', 'color': COLORS['warning']},
    
    # Blue-Green Deployment
    'Blue Env': {'pos': (0.65, 0.65), 'type': 'deployment', 'color': COLORS['primary']},
    'Green Env': {'pos': (0.65, 0.5), 'type': 'deployment', 'color': COLORS['success']},
    
    # DR Components
    'DR AMI': {'pos': (0.75, 0.65), 'type': 'dr', 'color': COLORS['secondary']},
    'DR EFS': {'pos': (0.75, 0.5), 'type': 'dr', 'color': COLORS['secondary']},
}

# Animation sequences
SEQUENCES = [
    # Phase 1: Security Scanning (frames 0-7)
    {'name': 'Security Scan', 'components': ['TFSec', 'Trivy', 'Checkov'], 'color': COLORS['accent']},
    
    # Phase 2: AMI Creation (frames 8-15)
    {'name': 'Golden AMI Build', 'components': ['Packer', 'Golden AMI'], 'color': COLORS['warning']},
    
    # Phase 3: Infrastructure Deployment (frames 16-23)
    {'name': 'Infrastructure Deploy', 'components': ['ALB', 'Jenkins ASG', 'EFS'], 'color': COLORS['primary']},
    
    # Phase 4: Blue-Green Deployment (frames 24-31)
    {'name': 'Blue-Green Deploy', 'components': ['Blue Env', 'Green Env'], 'color': COLORS['success']},
    
    # Phase 5: Disaster Recovery (frames 32-39)
    {'name': 'DR Sync', 'components': ['us-west-2', 'DR AMI', 'DR EFS'], 'color': COLORS['secondary']},
]

def create_glow_effect(ax, x, y, radius, color, alpha=0.3):
    """Create a glowing effect around components"""
    for i in range(3):
        glow = Circle((x, y), radius + i*0.02, 
                     facecolor=color, alpha=alpha/(i+1), 
                     edgecolor='none', zorder=1)
        ax.add_patch(glow)

def draw_component(ax, name, comp_data, active=False, glow=False):
    """Draw individual infrastructure component"""
    x, y = comp_data['pos']
    comp_type = comp_data['type']
    color = comp_data['color']
    
    # Component styling based on type
    if comp_type == 'region':
        # Large rounded rectangle for regions
        box = FancyBboxPatch((x-0.08, y-0.04), 0.16, 0.08,
                           boxstyle="round,pad=0.01",
                           facecolor=color if active else color + '40',
                           edgecolor=color, linewidth=2)
        ax.add_patch(box)
    else:
        # Circle for services
        radius = 0.03 if comp_type == 'security' else 0.04
        
        if glow:
            create_glow_effect(ax, x, y, radius, color)
        
        circle = Circle((x, y), radius,
                       facecolor=color if active else color + '40',
                       edgecolor=color, linewidth=2, zorder=2)
        ax.add_patch(circle)
    
    # Component label
    fontsize = 8 if comp_type == 'security' else 10
    ax.text(x, y-0.08, name, ha='center', va='top', 
           fontsize=fontsize, color=COLORS['text'], weight='bold')

def draw_data_flow(ax, start_comp, end_comp, progress=1.0, color=COLORS['primary']):
    """Draw animated data flow between components"""
    start_pos = COMPONENTS[start_comp]['pos']
    end_pos = COMPONENTS[end_comp]['pos']
    
    # Calculate intermediate position based on progress
    x1, y1 = start_pos
    x2, y2 = end_pos
    
    # Bezier curve for smooth flow
    mid_x = (x1 + x2) / 2
    mid_y = max(y1, y2) + 0.1
    
    # Draw flow line with progress
    if progress > 0:
        t = min(progress, 1.0)
        
        # Bezier curve calculation
        curve_x = (1-t)**2 * x1 + 2*(1-t)*t * mid_x + t**2 * x2
        curve_y = (1-t)**2 * y1 + 2*(1-t)*t * mid_y + t**2 * y2
        
        # Draw the flow line
        arrow = FancyArrowPatch((x1, y1), (curve_x, curve_y),
                              arrowstyle='-|>', mutation_scale=15,
                              color=color, linewidth=2, alpha=0.8)
        ax.add_patch(arrow)
        
        # Add flowing particles
        if progress > 0.5:
            particle = Circle((curve_x, curve_y), 0.01, 
                            facecolor=color, alpha=0.9, zorder=3)
            ax.add_patch(particle)

def create_frame(frame_num, total_frames):
    """Create a single frame of the animation"""
    fig, ax = plt.subplots(figsize=(12, 8))
    fig.patch.set_facecolor(COLORS['bg'])
    ax.set_facecolor(COLORS['bg'])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    
    # Title
    ax.text(0.5, 0.95, 'Jenkins Enterprise Platform - Luuul Solutions', 
           ha='center', va='center', fontsize=16, color=COLORS['text'], 
           weight='bold')
    
    # Subtitle with current phase
    current_phase = frame_num // 8
    if current_phase < len(SEQUENCES):
        phase_name = SEQUENCES[current_phase]['name']
        ax.text(0.5, 0.9, f'Phase: {phase_name}', 
               ha='center', va='center', fontsize=12, 
               color=SEQUENCES[current_phase]['color'])
    
    # Draw all components
    for name, comp_data in COMPONENTS.items():
        # Determine if component should be active/glowing
        active = False
        glow = False
        
        # Check if component is in current sequence
        if current_phase < len(SEQUENCES):
            sequence = SEQUENCES[current_phase]
            if name in sequence['components']:
                active = True
                # Add glow effect during active phase
                phase_progress = (frame_num % 8) / 8.0
                glow = phase_progress > 0.3
        
        draw_component(ax, name, comp_data, active, glow)
    
    # Draw data flows based on current phase
    flow_progress = (frame_num % 8) / 8.0
    
    if current_phase == 0:  # Security Scanning
        draw_data_flow(ax, 'TFSec', 'Packer', flow_progress, COLORS['accent'])
        draw_data_flow(ax, 'Trivy', 'Packer', flow_progress, COLORS['accent'])
        draw_data_flow(ax, 'Checkov', 'Packer', flow_progress, COLORS['accent'])
        
    elif current_phase == 1:  # AMI Creation
        draw_data_flow(ax, 'Packer', 'Golden AMI', flow_progress, COLORS['warning'])
        draw_data_flow(ax, 'Golden AMI', 'Jenkins ASG', flow_progress, COLORS['warning'])
        
    elif current_phase == 2:  # Infrastructure Deployment
        draw_data_flow(ax, 'ALB', 'Jenkins ASG', flow_progress, COLORS['primary'])
        draw_data_flow(ax, 'Jenkins ASG', 'EFS', flow_progress, COLORS['primary'])
        
    elif current_phase == 3:  # Blue-Green Deployment
        draw_data_flow(ax, 'Blue Env', 'Green Env', flow_progress, COLORS['success'])
        draw_data_flow(ax, 'Golden AMI', 'Blue Env', flow_progress, COLORS['success'])
        draw_data_flow(ax, 'Golden AMI', 'Green Env', flow_progress * 0.7, COLORS['success'])
        
    elif current_phase == 4:  # Disaster Recovery
        draw_data_flow(ax, 'us-east-1', 'us-west-2', flow_progress, COLORS['secondary'])
        draw_data_flow(ax, 'Golden AMI', 'DR AMI', flow_progress, COLORS['secondary'])
        draw_data_flow(ax, 'EFS', 'DR EFS', flow_progress, COLORS['secondary'])
    
    # Add metrics/stats
    stats_text = [
        "• 22 Terraform Modules",
        "• 3 Jenkins Pipelines", 
        "• Zero-Downtime Deployments",
        "• Multi-Region DR",
        "• 45% Cost Optimization"
    ]
    
    for i, stat in enumerate(stats_text):
        ax.text(0.02, 0.15 - i*0.03, stat, fontsize=9, 
               color=COLORS['text'], alpha=0.8)
    
    # Convert to image - Fixed for macOS compatibility
    fig.canvas.draw()
    
    # Get canvas buffer in a compatible way
    buf = fig.canvas.buffer_rgba()
    w, h = fig.canvas.get_width_height()
    image = np.frombuffer(buf, dtype=np.uint8).reshape((h, w, 4))
    # Convert RGBA to RGB
    image = image[:, :, :3]
    
    plt.close(fig)
    
    return image

def create_animated_architecture(filename="jenkins_enterprise_architecture.gif", 
                               total_frames=40, fps=10):
    """Create the complete animated architecture diagram"""
    print("🎬 Creating Jenkins Enterprise Platform Architecture Animation...")
    print(f"📊 Generating {total_frames} frames...")
    
    images = []
    for frame in range(total_frames):
        print(f"⚡ Frame {frame + 1}/{total_frames}", end='\r')
        img = create_frame(frame, total_frames)
        images.append(img)
    
    print(f"\n💾 Saving animation as {filename}...")
    imageio.mimsave(filename, images, fps=fps, loop=0)
    print(f"✅ Animation saved successfully!")
    print(f"📁 File: {filename}")
    print(f"🎯 Resolution: {images[0].shape[1]}x{images[0].shape[0]}")
    print(f"⏱️  Duration: {total_frames/fps:.1f} seconds")

if __name__ == "__main__":
    # Install required packages if needed
    try:
        import imageio
        import matplotlib
    except ImportError:
        print("📦 Installing required packages...")
        import subprocess
        subprocess.check_call(["pip", "install", "imageio", "matplotlib", "numpy"])
    
    # Create the animation
    create_animated_architecture(
        filename="jenkins_enterprise_architecture.gif",
        total_frames=40,  # 5 phases × 8 frames each
        fps=8  # Smooth but not too fast
    )
    
    print("\n🎉 Jenkins Enterprise Platform Architecture Animation Complete!")
    print("🔗 Perfect for your GitHub README and portfolio presentations!")
