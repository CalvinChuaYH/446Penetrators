import profile from "@/assets/default.jpeg";
import { Button } from "@/components/ui/button";
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import Navbar from "./components/navbar";
import { useState, useEffect, useRef } from "react";

function Settings() {
    const [profilePic, setProfilePic] = useState(profile);
    const [username, setUsername] = useState("");
    useEffect(() => {
        async function fetchUser() {
            try {
                const res = await fetch("http://localhost:5000/api/profile", {
                    headers: {
                        Authorization: `Bearer ${localStorage.getItem("token")}`
                    },
                });
                const data = await res.json();
                console.log(data);

                if (data.profile_pic) {
                    setProfilePic(data.profile_pic);
                }
                if (data.username) {
                    setUsername(data.username);
                }
            } catch (error) {
                // console.error("Error fetching user data:", error);
            }
        }
        fetchUser();
    }, []);

    const fileInputRef = useRef<HTMLInputElement>(null);
    const handleUploadFile = () => {
        fileInputRef.current?.click();
    }

    const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        // Instant preview
        // const url = URL.createObjectURL(file);
        // setProfilePic(url);

        // Optional: upload to backend
        const formData = new FormData();
        formData.append("profile_pic", file);
        formData.append("username", username);
        const res = await fetch("http://localhost:5000/api/upload", {
          method: "POST",
          headers: { Authorization: `Bearer ${localStorage.getItem("token")}` },
          body: formData,
        });
        const data = await res.json();
        if (data.profile_pic) {
            setProfilePic(data.profile_pic);
            alert(data.message);
        } else {
            alert(data.error || "Upload failed");
        }

        e.target.value = "";

    };


    return (
        <div className="flex flex-col items-center">
            <Navbar />

            <div className="flex flex-row justify-center items-center gap-50 h-screen">
            <div className="flex flex-col">
                <img src={profilePic} alt="profile" className="w-50 h-auto" />
                <input ref={fileInputRef} type="file" className="hidden" onChange={handleFileChange}/>
                <Button variant="outline" className="mt-4" onClick={handleUploadFile}>Change Profile Picture</Button>
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