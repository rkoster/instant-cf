# networking.star - Starlark functions for networking configuration

def set_static_ip(instance_group, ip, network_name="instant-cf"):
    """
    Set static IP for an instance group.
    
    Args:
        instance_group: The instance group to modify
        ip: Static IP address to assign
        network_name: Name of the Docker network (default: instant-cf)
    
    Returns:
        Modified instance group with static IP configured
    """
    instance_group["networks"] = [{
        "name": network_name,
        "static_ips": [ip]
    }]
    return instance_group
end

def set_static_ip_variable(instance_group, var_name, network_name="instant-cf"):
    """
    Set static IP as BOSH variable for runtime assignment.
    
    Args:
        instance_group: The instance group to modify
        var_name: Name of the BOSH variable (e.g., "database_ip")
        network_name: Name of the Docker network (default: instant-cf)
    
    Returns:
        Modified instance group with static IP as BOSH variable
    """
    instance_group["networks"] = [{
        "name": network_name,
        "static_ips": ["((" + var_name + "))"]
    }]
    return instance_group
end

def update_db_connection(jobs, db_host, db_port):
    """
    Update database connection strings in job properties.
    
    Common database link patterns in Cloud Foundry:
    - link("database") for postgres
    - address property patterns
    
    Args:
        jobs: List of job definitions
        db_host: Database host/IP address
        db_port: Database port number
    
    Returns:
        Modified jobs list with updated database connections
    """
    # This is a helper function - actual implementation will use overlays
    # in the YTT templates to update specific job properties
    return jobs
end

def update_blobstore_endpoint(jobs, endpoint):
    """
    Update blobstore endpoint configuration in job properties.
    
    Args:
        jobs: List of job definitions
        endpoint: Blobstore endpoint (hostname or IP)
    
    Returns:
        Modified jobs list with updated blobstore endpoints
    """
    # This is a helper function - actual implementation will use overlays
    # in the YTT templates to update specific job properties
    return jobs
end

def get_network_config(network_name, subnet, gateway):
    """
    Generate network configuration for BOSH manifest.
    
    Args:
        network_name: Name of the network
        subnet: Network subnet in CIDR notation
        gateway: Gateway IP address
    
    Returns:
        Network configuration dict
    """
    return {
        "name": network_name,
        "type": "manual",
        "subnets": [{
            "range": subnet,
            "gateway": gateway,
            "azs": ["z1"],
            "static": [],  # Static IPs will be assigned per instance group
            "reserved": []
        }]
    }
end

def add_static_ip_to_network(network, ip):
    """
    Add a static IP to network's static IP pool.
    
    Args:
        network: Network configuration dict
        ip: IP address to add to static pool
    
    Returns:
        Modified network configuration
    """
    if len(network["subnets"]) > 0:
        if "static" not in network["subnets"][0]:
            network["subnets"][0]["static"] = []
        network["subnets"][0]["static"].append(ip)
    return network
end

def get_static_ips_from_values(data_values, phase):
    """
    Get appropriate static IPs based on deployment phase.
    
    Phase 1: 3 containers (database, control, runtime)
    Phase 2a: 2 containers (data=database, platform=control)  
    Phase 2b: 1 container (all=database)
    
    Args:
        data_values: YTT data values
        phase: Deployment phase (1, 2a, 2b)
    
    Returns:
        Dict mapping container names to IPs
    """
    if phase == "1":
        return {
            "database": data_values.network.ips.database,
            "control": data_values.network.ips.control,
            "runtime": data_values.network.ips.runtime
        }
    elif phase == "2a":
        # Phase 2a: data container (database+blobstore) and platform container (control+runtime)
        return {
            "data": data_values.network.ips.database,
            "platform": data_values.network.ips.control
        }
    elif phase == "2b":
        # Phase 2b: Single all-in-one container
        return {
            "all": data_values.network.ips.database
        }
    else:
        fail("Unknown phase: " + phase)
    end
end
