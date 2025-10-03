import {
    NavigationMenu,
    NavigationMenuContent,
    NavigationMenuIndicator,
    NavigationMenuItem,
    NavigationMenuLink,
    NavigationMenuList,
    NavigationMenuTrigger,
    NavigationMenuViewport,
  } from "@/components/ui/navigation-menu"
import { Link } from "react-router-dom";
import {
    Card,
    CardAction,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
  } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import profile from "@/assets/default.jpeg"


function Settings() {
    return (
        <div className="flex flex-col items-center">
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
                </NavigationMenuList>
            </NavigationMenu>

            <div className="flex flex-row justify-center items-center gap-50 h-screen">
            <div className="flex flex-col">
                <img src={profile} alt="profile" />
                <Button variant="outline" className="mt-4">Change Profile Picture</Button>
            </div>

            <Card className="w-[400px]">
                <CardHeader>
                    <CardTitle>Profile Settings</CardTitle>
                    <CardDescription>Change your profile settings</CardDescription>
                </CardHeader>
                <CardContent>
                <form>
                    <div className="flex flex-col gap-6">
                        <div className="grid gap-2">
                        <Label htmlFor="email">Username</Label>
                        <Input
                            id="username"
                            type="username"
                            placeholder=""
                            required
                        />
                        </div>
                        <div className="grid gap-2">
                        <div className="flex items-center">
                            <Label htmlFor="password">Password</Label>
                        </div>
                        <Input id="password" type="password" required />
                        </div>
                    </div>
                    <Button type="submit" variant="outline" className="mt-4">
                        Save Changes
                    </Button>
                    </form>
                </CardContent>
            </Card>
            </div>
        </div>
    )
}

export default Settings;