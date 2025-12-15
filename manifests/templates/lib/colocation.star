# colocation.star - Starlark functions for instance group colocation

def merge_instance_groups(manifest, group_names, new_name):
    """
    Merge multiple instance groups into a single colocated instance group.
    
    Args:
        manifest: The full cf-deployment manifest
        group_names: List of instance group names to merge
        new_name: Name for the new merged instance group
    
    Returns:
        A new instance group with all jobs from the specified groups
    """
    merged_jobs = []
    
    # Extract all jobs from the specified instance groups
    for ig in manifest["instance_groups"]:
        if ig["name"] in group_names:
            merged_jobs.extend(ig.get("jobs", []))
    
    return {
        "name": new_name,
        "instances": 1,
        "jobs": merged_jobs
    }
end

def extract_jobs(instance_group):
    """
    Extract all jobs from an instance group.
    
    Args:
        instance_group: The instance group to extract jobs from
    
    Returns:
        List of job definitions
    """
    return instance_group.get("jobs", [])
end

def set_instances(instance_group, count):
    """
    Set the instance count for an instance group.
    
    Args:
        instance_group: The instance group to modify
        count: Number of instances to set
    
    Returns:
        Modified instance group
    """
    instance_group["instances"] = count
    return instance_group
end

def filter_instance_groups(manifest, group_names):
    """
    Filter instance groups to keep only specified ones.
    
    Args:
        manifest: The full cf-deployment manifest
        group_names: List of instance group names to keep
    
    Returns:
        List of filtered instance groups
    """
    filtered = []
    for ig in manifest["instance_groups"]:
        if ig["name"] in group_names:
            filtered.append(ig)
    return filtered
end

def remove_instance_groups(manifest, group_names):
    """
    Remove specified instance groups from manifest.
    
    Args:
        manifest: The full cf-deployment manifest
        group_names: List of instance group names to remove
    
    Returns:
        Manifest with specified groups removed
    """
    filtered = []
    for ig in manifest["instance_groups"]:
        if ig["name"] not in group_names:
            filtered.append(ig)
    manifest["instance_groups"] = filtered
    return manifest
end

def get_jobs_from_groups(manifest, group_names):
    """
    Get all jobs from specified instance groups.
    
    Args:
        manifest: The full cf-deployment manifest
        group_names: List of instance group names
    
    Returns:
        List of all jobs from the specified groups
    """
    all_jobs = []
    for ig in manifest["instance_groups"]:
        if ig["name"] in group_names:
            all_jobs.extend(ig.get("jobs", []))
    return all_jobs
end
