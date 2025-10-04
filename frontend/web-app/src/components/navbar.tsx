import {
    NavigationMenu,
    NavigationMenuItem,
    NavigationMenuList,
    NavigationMenuTrigger
} from "@/components/ui/navigation-menu";
import { Link, useNavigate } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { Navigation } from "lucide-react";

function Navbar() {

    const navigate = useNavigate();

    const handleLogout = () => {
        localStorage.removeItem("token");
        navigate("/");
    }
    return (
        <NavigationMenu className="">
            <NavigationMenuList>
                <NavigationMenuItem>
                <NavigationMenuTrigger>
                    <Link to="/home">Home</Link>
                </NavigationMenuTrigger>
                <NavigationMenuTrigger>
                    <Link to="/settings">Settings</Link>
                </NavigationMenuTrigger>
                </NavigationMenuItem>
                <NavigationMenuItem>
                    <Button type="submit" variant="link" onClick={handleLogout} >Logout</Button>
                </NavigationMenuItem>

            </NavigationMenuList>
        </NavigationMenu>
    )
}

export default Navbar;